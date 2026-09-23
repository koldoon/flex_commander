import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Упаковать выбранное в архив — **в каталог своей же панели**.
///
/// Одна команда на все форматы: место — свойство заявки, а не формата, и
/// палитра из четырёх строк, говорящих одно и то же, никому не нужна
/// (`docs/spec/archive-here.md`, §4).
class PackHereCommand extends AppCommand {
  PackHereCommand(this.packers);

  static const String commandId = 'archive.packHere';

  /// Доводы для тех, кто зовёт команду мимо окна: сценарий, палитра с
  /// параметрами, проверка. Заданы — работа идёт сразу
  /// (`docs/spec/archive-here.md`, §4).
  static const String nameParam = 'name';
  static const String formatParam = 'format';
  static const String followLinksParam = 'followLinks';

  /// Объявленные упаковщики. Пусто — команды нет: паковать нечем.
  final Packers packers;

  @override
  String get id => commandId;

  @override
  String get label => tr('Pack here');

  @override
  String get description => tr('Pack the selected items into an archive in this very panel');

  @override
  Set<String> get keywords => const {'compress', 'zip', 'tar', '7z'};

  @override
  bool isExecutable(CommandContext context) {
    final panel = context.session;
    return packers.all.isNotEmpty &&
        !panel.busy &&
        panel.hasTargets &&
        panel.source.contentKind == SourceInfo.files &&
        panel.source.canReceive &&
        panel.currentPath.isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final formats = packers.all;
    if (formats.isEmpty || !panel.hasTargets) {
      return;
    }
    // Имя задано — окна не будет: параметром зовут не люди, и смотреть его
    // некому.
    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      await _packWith(
        context,
        format: _formatOf(context.invocation.param<String>(formatParam)),
        name: given,
        followLinks: context.invocation.param<bool>(followLinksParam) ?? false,
        choice: null,
      );
      return;
    }
    final where = panel.currentPath;
    final view = context.app.view;
    final title = tr('Pack here');
    late final _PackRun run;

    Future<void> pack() => _packWith(
      context,
      format: run.format,
      name: run.name,
      followLinks: run.followLinks,
      choice: run.choiceOf(run.format),
      run: run,
    );

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: title,
          takesFocus: true,
          content: FcAsyncRunDialog(run: run, form: (_) => _PackForm(run: run, where: where)),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = _PackRun(
      app: context.app,
      commandId: id,
      title: title,
      failureMessage: '${tr('Pack here')} ${tr('failed')}',
      show: present,
      formats: formats,
    );
    run.onStart = pack;
    present();
  }

  /// Формат по имени; не назвали или не знаем такого — первый объявленный.
  PackerSpec _formatOf(String? id) =>
      packers.all.firstWhere((format) => format.id == id, orElse: () => packers.all.first);

  /// Сама заявка — одна на оба пути: из окна и мимо него.
  Future<void> _packWith(
    CommandContext context, {
    required PackerSpec format,
    required String name,
    required bool followLinks,
    required String? choice,
    FcAsyncRun? run,
  }) async {
    final panel = context.session;
    // Снимком: пока открыто окно, панель уходит куда угодно, а человек видел
    // то, что видел (`docs/spec/client-server.md`, §5.6а).
    final where = panel.currentPath;
    final full = _withExtension(name.trim(), format.extension);
    if (full.isEmpty || full.contains('/') || full.contains(r'\')) {
      throw FsError(full, FsErrorKind.invalidName);
    }
    final spec = OperationSpec(
      kind: format.kind,
      targets: Targets.marked(panel.id, under: panel.currentRef),
      destination: Destination.inPanel(panel.id, path: where),
      options: {
        format.nameOption: full,
        format.followLinksOption: followLinks,
        if (format.choice case final option?) option.option: choice ?? option.fallback,
      },
    );

    final operation = context.app.runOperation();
    if (run != null) {
      await run.run(operation, spec, message: tr('Packing…'));
    } else {
      await operation.run(spec);
    }
    // Панель показывает не то, что на диске: там появился архив.
    await reloadPanelsAt(context.app, [where]);
  }

  /// Дописывает расширение формата, если человек своего не написал.
  static String _withExtension(String name, String extension) {
    if (name.isEmpty || extension.isEmpty) {
      return name;
    }
    return name.toLowerCase().endsWith('.${extension.toLowerCase()}') ? name : '$name.$extension';
  }
}

/// Прогон упаковки: имя, формат и его довод живут здесь, пока открыто окно.
class _PackRun extends FcAsyncRun {
  _PackRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.formats,
  }) : format = formats.first;

  final List<PackerSpec> formats;

  String name = '';

  /// Ссылки: по умолчанию ложатся в архив ссылками, как в mc.
  bool followLinks = false;

  PackerSpec format;

  /// Выбранное значение довода — своё у каждого формата: сменил формат и
  /// вернулся, а выбранное на месте.
  final Map<String, String> _choices = {};

  String choiceOf(PackerSpec spec) => _choices[spec.id] ?? spec.choice?.fallback ?? '';

  void setFormat(PackerSpec value) {
    format = value;
    notifyListeners();
  }

  void setChoice(String value) {
    _choices[format.id] = value;
    notifyListeners();
  }

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }
}

/// Форма упаковки: куда (не правится), имя, формат и довод формата.
class _PackForm extends StatefulWidget {
  const _PackForm({required this.run, required this.where});

  final _PackRun run;
  final String where;

  @override
  State<_PackForm> createState() => _PackFormState();
}

class _PackFormState extends State<_PackForm> {
  late final TextEditingController _name = TextEditingController(text: widget.run.name);
  late final TextEditingController _where = TextEditingController(text: widget.where);

  @override
  void dispose() {
    _name.dispose();
    _where.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final choice = run.format.choice;

    return CommandDialogForm(
      error: run.error,
      onCancel: run.dismiss,
      onSubmit: run.submit,
      submitLabel: context.strings.tr('Create'),
      children: [
        CommandDialogField(
          label: context.strings.tr('Create in'),
          child: FcTextField(controller: _where, enabled: false),
        ),
        CommandDialogField(
          label: context.strings.tr('Archive name'),
          child: FcTextField(
            controller: _name,
            autofocus: true,
            hintText: 'archive.${run.format.extension}',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField(
          label: context.strings.tr('Format'),
          child: FcSelect<PackerSpec>(
            options: {for (final format in run.formats) format: format.title},
            value: run.format,
            onChanged: run.setFormat,
          ),
        ),
        if (choice != null)
          CommandDialogField(
            label: context.strings.tr(choice.label),
            child: FcSelect<String>(
              // Названия значений приходят объявлением — переводит их тот, кто
              // показывает.
              options: {for (final value in choice.values) value.value: context.strings.tr(value.title)},
              value: run.choiceOf(run.format),
              onChanged: run.setChoice,
            ),
          ),
        CommandDialogField.wide(
          child: FcCheckbox(
            label: context.strings.tr('Follow symlinks'),
            value: run.followLinks,
            onChanged: run.setFollowLinks,
          ),
        ),
      ],
    );
  }
}
