import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'tar_format.dart';
import 'tar_pack.dart';

/// Расширения, которые считаются уже написанным именем архива.
///
/// Порядок важен: `.tar.gz` длиннее `.tar` и потому проверяется раньше — иначе
/// от `src.tar.gz` отрезалось бы только `.gz`.
const List<String> _tarExtensions = ['.tar.gz', '.tgz', '.tar'];

/// Упаковать выбранное в новый tar-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Клавиши команде не досталось: `Shift-F5` занял zip, `Shift-F7` — 7z, а
/// `Shift-F6` встал бы поперёк привычки — `F6` в коммандерах это перенос.
/// Команда живёт в палитре, ровно тот случай, ради которого палитра и
/// заводилась.
class CreateTarArchiveCommand extends AppCommand {
  CreateTarArchiveCommand();

  static const String commandId = 'tar.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Формат — имя значения [TarFormat].
  static const String formatParam = 'format';

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка ложится в
  /// архив ссылкой — tar это умеет, и ради этого им и пользуются.
  static const String followLinksParam = 'followLinks';

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Tar';

  @override
  String get description => 'Pack the selected items into a new tar, tar.gz or tgz archive';

  /// Ищут её и по тому, что она умеет: `.tar.gz` в названии не помещается, а
  /// набирают в палитре чаще всего именно `gz`.
  @override
  Set<String> get keywords => const {'tar.gz', 'tgz', 'gzip', 'archive', 'compress', 'pack'};

  String get dialogTitle => 'Create TAR archive';

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy || _sourcesOf(context).isEmpty) {
      return false;
    }
    // Класть архив некуда, если приёмника нет вовсе (панель накрыта показом)
    // или он не умеет принимать содержимое.
    // Занятый приёмник принять ничего не может: он сам сейчас читает.
    final target = context.target;
    return target != null && !target.busy && target.path.isNotEmpty && target.source.canReceive;
  }

  /// Что паковать: помеченное, а без пометки — то, что под курсором.
  List<FileEntry> _sourcesOf(CommandContext context) => [
    for (final entry in context.targets)
      if (!entry.isParent) entry,
  ];

  @override
  Future<void> execute(CommandContext context) async {
    final target = context.target;
    if (_sourcesOf(context).isEmpty || target == null) {
      return;
    }

    Future<void> pack(String typed, TarFormat format, bool followLinks, [FcAsyncRun? run]) async {
      final name = withExtension(typed, format);
      if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      // Аренда обоих концов и проверка занятого имени — дело ядра: там живут
      // узлы, и там же идёт работа.
      final spec = OperationSpec(
        kind: TarPacking.kind,
        targets: Targets.marked(context.panel.id),
        destination: target.id,
        options: {
          TarPacking.nameOption: name,
          TarPacking.formatOption: format.name,
          TarPacking.followLinksOption: followLinks,
        },
      );

      final operation = context.app.runOperation();
      if (run != null) {
        await run.run(operation, spec, message: 'Packing…');
      } else {
        await operation.run(spec);
      }

      // Приёмник теперь показывает не то, что на диске: там появился архив.
      await target.reload();
    }

    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      await pack(
        given,
        TarFormat.byName(context.invocation.param<String>(formatParam)),
        context.invocation.param<bool>(followLinksParam) ?? false,
      );
      return;
    }

    final view = context.app.view;
    late final _CreateArchiveRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(
          title: dialogTitle,
          takesFocus: true,
          content: FcAsyncRunDialog(run: run, form: (_) => _CreateArchiveForm(run: run)),
          onSubmit: run.submit,
          onDismiss: run.dismiss,
        ),
      );
    }

    run = _CreateArchiveRun(
      app: context.app,
      commandId: id,
      title: dialogTitle,
      failureMessage: '$label failed',
      show: present,
      name: defaultNameOf(context),
      destinationPath: destinationPathOf(context),
    );
    run.onStart = () => pack(run.name, run.format, run.followLinks, run);

    present();
  }

  /// Имя архива вместе с расширением выбранного формата.
  ///
  /// Расширение не приписывается, а **заменяется**: набранное имя может уже
  /// кончаться архивным расширением — своим или чужим. Иначе `src.tar.gz` при
  /// том же формате стало бы `src.tar.gz.tar.gz`, а при переключении на `.tgz`
  /// — `src.tar.gz.tgz`, то есть именем, которое врёт о содержимом.
  @visibleForTesting
  static String withExtension(String raw, TarFormat format) {
    final typed = withoutExtension(raw);
    return typed.isEmpty ? '' : '$typed${format.extension}';
  }

  /// Имя без архивного расширения, каким бы из трёх оно ни было.
  @visibleForTesting
  static String withoutExtension(String raw) {
    final typed = raw.trim();
    final lower = typed.toLowerCase();
    for (final suffix in _tarExtensions) {
      if (lower.endsWith(suffix)) {
        return typed.substring(0, typed.length - suffix.length);
      }
    }
    return typed;
  }

  /// Имя, предложенное по умолчанию: по единственному объекту или по каталогу,
  /// из которого пакуем, — как в референсных менеджерах.
  String defaultNameOf(CommandContext context) {
    final sources = _sourcesOf(context);
    if (sources.length == 1) {
      return '${sources.single.name}${TarFormat.gzip.extension}';
    }
    final directory = context.panel.directoryName;
    final name = directory.isEmpty || directory == '/' ? 'archive' : directory;
    return '$name${TarFormat.gzip.extension}';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String destinationPathOf(CommandContext context) => context.target?.path ?? '';
}

/// Прогон упаковки вместе с тем, что спрашивают до её начала.
class _CreateArchiveRun extends FcAsyncRun {
  _CreateArchiveRun({
    required super.app,
    required super.commandId,
    required super.title,
    required super.failureMessage,
    required super.show,
    required this.name,
    required this.destinationPath,
  });

  String name;

  /// Куда ляжет архив. Не редактируется — приёмник задан панелью.
  final String destinationPath;

  /// Ссылки: по умолчанию ложатся в архив ссылками — tar это умеет.
  bool followLinks = false;

  TarFormat format = TarFormat.gzip;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }

  void setFormat(TarFormat value) {
    // Имя идёт за форматом: выбрал `.tar` — расширение в поле меняется тут же,
    // иначе человек получил бы `.tar.gz` с несжатым содержимым.
    name = CreateTarArchiveCommand.withExtension(name, value);
    format = value;
    notifyListeners();
  }
}

/// Форма создания архива: имя, формат и ссылки.
class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.run});

  final _CreateArchiveRun run;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  late final TextEditingController _name = TextEditingController(text: widget.run.name);
  late final TextEditingController _destination = TextEditingController(text: widget.run.destinationPath);

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    // Поле идёт за выбором формата: имя меняет не человек, а переключатель.
    if (_name.text != run.name) {
      _name.value = TextEditingValue(text: run.name, selection: TextSelection.collapsed(offset: run.name.length));
    }

    return CommandDialogForm(
      error: run.error,
      onCancel: run.dismiss,
      onSubmit: run.submit,
      submitLabel: 'Create',
      children: [
        CommandDialogField(label: 'Create in', child: FcTextField(controller: _destination, enabled: false)),
        CommandDialogField(
          label: 'Archive name',
          child: FcTextField(
            controller: _name,
            autofocus: true,
            hintText: 'archive.tar.gz',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField(
          label: 'Format',
          child: FcRadioGroup<TarFormat>(
            direction: Axis.horizontal,
            options: {for (final value in TarFormat.values) value: value.title},
            value: run.format,
            onChanged: run.setFormat,
          ),
        ),
        CommandDialogField.wide(
          child: FcCheckbox(label: 'Follow symlinks', value: run.followLinks, onChanged: run.setFollowLinks),
        ),
      ],
    );
  }
}
