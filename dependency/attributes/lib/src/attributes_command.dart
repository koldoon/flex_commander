import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'attribute_edits.dart';
import 'attributes_form.dart';
import 'attributes_run.dart';

/// Правка атрибутов — окном.
///
/// `Ctrl-A` — привычка Far Manager, где за ней ровно эти самые атрибуты файла.
/// Обоих «маковских» кандидатов занял этап сведений: `Cmd-I` и `Alt-Enter`
/// открывают их, и отбирать клавишу у чтения ради правки нельзя — смотрят
/// чаще, чем правят.
class AttributesCommand extends AppCommand {
  static const String commandId = 'file.attributes';

  /// Идти ли внутрь каталогов — параметром, мимо окна.
  static const String recursiveParam = AttributeOperations.recursive;

  @override
  String get id => commandId;

  @override
  String get label => tr('Attributes');

  @override
  Set<String> get keywords => const {'chmod', 'permissions', 'rights', 'owner', 'xattr', 'mode'};

  @override
  String get description => tr('Change permissions, dates, owner and extended attributes');

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    // Умеет ли источник хоть что-то из четырёх, известно только про объект, а
    // не про панель: спросить об этом заранее нечем. Поэтому здесь — то, что
    // видно отсюда: есть цель, и источник вообще умеет меняться.
    return !panel.busy && panel.source.canWrite && _targetsOf(context).isNotEmpty;
  }

  /// Помеченное, а нет пометки — то, что под курсором. «..» не в счёт: это
  /// чужой каталог, и правка под его именем была бы подменой.
  List<FileEntry> _targetsOf(CommandContext context) => [
    for (final entry in context.targets)
      if (!entry.isParent) entry,
  ];

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final targets = _targetsOf(context);
    if (targets.isEmpty) {
      return;
    }

    final view = context.app.view;
    final title =
        targets.length == 1 ? targets.single.name : plural(targets.length, one: '{n} item', other: '{n} items');
    late final AttributesRun run;

    Future<void> apply() async {
      final edits = run.collect(context.app.strings);
      if (edits == null) {
        // В полях негодное: работу не заводим, а причину говорим тостом.
        run.complain(context.app.toasts);
        return;
      }
      if (edits.isEmpty) {
        // Открыли и закрыли, ничего не тронув: заводить работу незачем.
        run.close?.call();
        return;
      }
      try {
        await run.run(
          // Без своего имени: второй заход после отказа — это **другая**
          // работа, и ядро не должно принять её за уже законченную.
          context.app.runOperation(),
          OperationSpec(kind: AttributeOperations.apply, targets: Targets.marked(panel.id), options: edits.toOptions()),
          message: tr('Changing attributes…'),
        );
      } finally {
        // Панели показывают не то, что на диске: права и даты изменились.
        await _reload(context.app, targets);
      }
      // Отказ (работа отказалась, не начавшись) — тостом. Строка внутри формы
      // отъедала бы у неё место и двигала поля ровно тогда, когда в них
      // собираются что-то поправить.
      run.complain(context.app.toasts);
    }

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: title,
          takesFocus: true,
          // Ширина назначена окном, а не содержимым: и форма, и ход работы, и
          // вопрос при отказе стоят в одной раме, и дёргаться ей незачем.
          content: SizedBox(
            width: AttributesForm.width,
            child: FcAsyncRunDialog(run: run, form: (_) => AttributesForm(run: run)),
          ),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = AttributesRun(
      app: context.app,
      commandId: id,
      title: tr('Attributes'),
      failureMessage: tr('Changing attributes failed'),
      show: present,
      targets: targets,
    );
    run.onStart = apply;
    // Параметром — мимо окна: правка дерева выразима и из палитры, и из
    // привязки клавиши.
    run.recursive = context.invocation.param<bool>(recursiveParam) ?? false;

    present();
    // Окно уже стоит — теперь можно и спросить, что там на самом деле.
    unawaited(_probe(panel, run));
  }

  /// Свежие атрибуты первой цели и исходная сетка прав.
  ///
  /// Спрашивается **первая**: у неё же берутся умения источника. Сетка при
  /// одной цели строится по прочитанному, при нескольких — по тому, что уже
  /// показано в списке. Спрашивать заново про каждую из десяти тысяч
  /// помеченных строк значило бы столько же разговоров через границу, а сетке
  /// нужно ровно одно — совпал бит или нет.
  Future<void> _probe(Session panel, AttributesRun run) async {
    try {
      final sample = await panel.readAttributes(run.targets.first);
      run.adopt(
        sample,
        modes: run.targets.length == 1 ? [sample.mode] : [for (final entry in run.targets) entry.attributes.mode],
      );
    } on FsError catch (error) {
      run.failed(error);
    }
  }

  /// Перечитать панели, которые смотрят на задетые каталоги.
  Future<void> _reload(Application app, List<FileEntry> targets) async {
    final directories = {for (final entry in targets) entry.directoryPath};
    for (final session in [app.left, app.right]) {
      if (directories.contains(session.currentPath)) {
        await session.reload();
      }
    }
  }
}
