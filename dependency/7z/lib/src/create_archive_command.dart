import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'seven_zip_compression.dart';
import 'seven_zip_pack.dart';

/// Упаковать выбранное в новый 7z-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Упаковывает не модуль, а программа, и работать она умеет только с файлами на
/// диске. Поэтому источники, у которых настоящего пути нет (другой архив,
/// сервер), сперва выкладываются во временный каталог — за это приходится
/// платить лишним проходом по байтам, и в ходе работы это видно.
class CreateSevenZipArchiveCommand extends AppCommand {
  CreateSevenZipArchiveCommand();

  static const String commandId = '7z.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Степень сжатия — имя значения [SevenZipCompression].
  static const String compressionParam = 'compression';

  /// Идти ли по символическим ссылкам. По умолчанию нет — и тогда программе
  /// нужен ключ `-snl`: сама по себе она ссылки разыменовывает.
  static const String followLinksParam = 'followLinks';

  @override
  String get id => commandId;

  @override
  String get label => 'Mk 7z';

  @override
  String get description => 'Pack the selected items into a new 7z archive';

  /// `7zip` и `seven` — то же имя, набранное иначе; остальное общее для всех
  /// упаковщиков.
  @override
  Set<String> get keywords => const {'7zip', 'seven zip', 'archive', 'compress', 'pack', 'lzma'};

  String get dialogTitle => 'Create 7z archive';

  /// Окно начинается с формы, и фокус нужен полю имени.

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

    Future<void> pack(String typed, SevenZipCompression compression, bool followLinks, [FcAsyncRun? run]) async {
      final name = _withExtension(typed);
      if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      // Аренда обоих концов и проверка занятого имени — дело ядра: там живут
      // узлы, и там же идёт работа.
      final spec = OperationSpec(
        kind: SevenZipPacking.kind,
        targets: Targets.marked(context.panel.id),
        destination: target.id,
        options: {
          SevenZipPacking.nameOption: name,
          SevenZipPacking.compressionOption: compression.name,
          SevenZipPacking.followLinksOption: followLinks,
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
        SevenZipCompression.byName(context.invocation.param<String>(compressionParam)),
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
    run.onStart = () => pack(run.name, run.compression, run.followLinks, run);

    present();
  }

  /// Имя архива: пустое расширение дописывается само — команда всё-таки
  /// называется «create 7z archive».
  static String _withExtension(String raw) {
    final typed = raw.trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.7z') ? typed : '$typed.7z';
  }

  // --- окно ---

  /// Вопрос по ходу работы, ход дела и разбор ошибки — общие для всех
  /// длительных работ: упаковка ничем не отличается от копирования, и
  /// рассказывать о ней иначе незачем. Своё у команды одно — форма.
  /// Имя, предложенное по умолчанию: по единственному объекту или по каталогу,
  /// из которого пакуем, — как в референсных менеджерах.
  String defaultNameOf(CommandContext context) {
    final sources = _sourcesOf(context);
    if (sources.length == 1) {
      return '${sources.single.name}.7z';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name.7z';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String destinationPathOf(CommandContext context) => context.target?.path ?? '';
}

/// Имя записи из строки вывода программы.
///

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

  /// Ссылки: по умолчанию ложатся в архив ссылками, как в mc.
  bool followLinks = false;

  SevenZipCompression compression = SevenZipCompression.normal;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }

  void setCompression(SevenZipCompression value) {
    compression = value;
    notifyListeners();
  }
}

/// Форма создания архива: имя и степень сжатия.
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
            hintText: 'archive.7z',
            onChanged: (value) => run.name = value,
            onSubmitted: (_) => run.submit(),
          ),
        ),
        CommandDialogField.wide(
          child: FcCheckbox(label: 'Follow symlinks', value: run.followLinks, onChanged: run.setFollowLinks),
        ),
        CommandDialogField(
          label: 'Compression',
          // Выпадающим списком, а не переключателем: степеней сжатия столько,
          // сколько их у упаковщика, и строка на каждую растила бы окно вместе
          // с их числом (`docs/widgets.md`).
          child: FcSelect<SevenZipCompression>(
            options: {for (final value in SevenZipCompression.values) value: value.title},
            value: run.compression,
            onChanged: run.setCompression,
          ),
        ),
      ],
    );
  }
}
