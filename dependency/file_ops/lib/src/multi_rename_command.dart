import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'multi_rename_form.dart';
import 'rename_batch.dart';
import 'rename_plan.dart';

/// Переименовать помеченное разом — по маске, с предпросмотром.
///
/// Окно показывает **две колонки, было и станет**, строка в строку, и до
/// нажатия на диске не меняется ничего (`docs/spec/multi-rename.md`).
class MultiRenameCommand extends AppCommand {
  MultiRenameCommand(this.naming);

  static const String commandId = 'file.renameBatch';

  /// Как имя делится на основу и расширение — та же служба, что рисует колонку
  /// расширения: составные расширения (`архив.tar.gz`) разбирает она.
  final FileNaming naming;

  @override
  String get id => commandId;

  @override
  String get label => tr('Multi-rename');

  @override
  String get description => tr('Rename the selected items at once, with a preview');

  @override
  Set<String> get keywords => const {'batch', 'mask', 'counter', 'pattern'};

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    return !panel.busy &&
        panel.source.canWrite &&
        panel.source.capabilities.canRename &&
        panel.source.contentKind == SourceInfo.files &&
        panel.hasTargets;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    if (!panel.hasTargets) {
      return;
    }
    final view = context.app.view;
    late final MultiRenameRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: tr('Multi-rename'),
          // Размер окна переживает перезапуск: таблицу предпросмотра тянут
          // первым делом, имена длинные.
          id: commandId,
          resizable: true,
          takesFocus: true,
          // Ширину назначает само окно, долей экрана: иначе рама мерила бы
          // содержимое, а ленивый список на вопрос о своей ширине не отвечает.
          ownWidth: true,
          content: FcAsyncRunDialog(run: run, form: (_) => MultiRenameForm(run: run)),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = MultiRenameRun(
      app: context.app,
      commandId: id,
      title: tr('Multi-rename'),
      failureMessage: '${tr('Multi-rename')} ${tr('failed')}',
      show: present,
      naming: naming,
      panel: panel,
    );
    run.onStart = () => _apply(context, run);

    present();
    // Цели и занятые имена спрашиваются **после** показа окна: оно должно
    // встать сразу, а таблица работает и до ответа (§8).
    unawaited(run.collect());
  }

  Future<void> _apply(CommandContext context, MultiRenameRun run) async {
    final panel = context.session;
    final plan = run.plan;
    final renames = plan.renames;
    if (renames.isEmpty) {
      return;
    }
    // Каталоги спрашиваются до работы: после неё этих строк уже нет.
    final places = {for (final row in plan.rows) row.entry.directoryPath};
    final first = plan.rows.firstWhere((row) => row.status == RenameStatus.renamed).to;

    try {
      await run.run(
        context.app.runOperation(),
        OperationSpec(
          kind: RenameOperations.batch,
          targets: Targets.marked(panel.id, under: panel.currentRef),
          options: RenameBatch.of(renames).toOptions(),
        ),
        message: tr('Renaming…'),
      );
    } finally {
      await reloadPanelsAt(context.app, places.toList());
      // Пометка жила путями, а пути изменились все разом (§10).
      panel.clearMarks(by: MarkChange.work);
      panel.setCursorToName(first);
    }
  }
}

/// Прогон группового переименования: что набрано, что из этого выйдет и сама
/// работа.
class MultiRenameRun extends FcAsyncRun {
  MultiRenameRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.naming,
    required this.panel,
  });

  final FileNaming naming;
  final Session panel;

  /// Цели — в том порядке, в каком их видно в панели: по нему считается номер.
  List<FileEntry> entries = const [];

  /// Занятые имена по каталогам; пока не спросили — проверка не строга.
  Map<String, Set<String>> taken = const {};

  RenameSpec spec = const RenameSpec();

  RenamePlan get plan => RenamePlan.build(entries, spec, naming: naming, taken: taken);

  /// Можно ли применять: есть что менять и не с чем спорить.
  bool get canApply => spec.isValid && plan.changes > 0 && !plan.hasCollisions;

  /// Спросить цели и то, что уже лежит в их каталогах.
  Future<void> collect() async {
    entries = [
      for (final entry in await panel.allTargets())
        if (!entry.isParent) entry,
    ];
    notifyListeners();

    final places = {for (final entry in entries) entry.directoryPath};
    final occupied = <String, Set<String>>{};
    for (final place in places) {
      occupied[place] = {for (final entry in await panel.namesIn(place)) entry.name};
    }
    taken = occupied;
    notifyListeners();
  }

  void edit(RenameSpec value) {
    spec = value;
    notifyListeners();
  }
}
