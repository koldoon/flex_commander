import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'zip_compression.dart';
import 'zip_pack.dart';

/// Упаковать выбранное в новый zip-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Источники могут лежать где угодно, в том числе в другом архиве: содержимое
/// берётся через [LocalCopySession], а она сама решает, есть ли у файла
/// настоящий путь или его придётся выложить во временный.
class CreateZipArchiveCommand extends AppCommand {
  CreateZipArchiveCommand();

  static const String commandId = 'zip.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Степень сжатия — имя значения [ZipCompression].
  static const String compressionParam = 'compression';

  /// Идти ли по символическим ссылкам. По умолчанию нет: ссылка ложится в
  /// архив ссылкой, как в mc.
  static const String followLinksParam = 'followLinks';

  @override
  String get id => commandId;

  @override
  String get label => 'Mk Zip';

  @override
  String get description => 'Pack the selected items into a new zip archive';

  /// Ищут упаковщик и по делу, а не только по формату: «archive», «compress»,
  /// «pack» — слова, которые приходят в голову раньше, чем `zip`.
  @override
  Set<String> get keywords => const {'archive', 'compress', 'pack'};

  String get dialogTitle => 'Create ZIP archive';

  /// Окно начинается с формы, и фокус нужен полю имени.

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy || _sourcesOf(context).isEmpty) {
      return false;
    }
    // Класть архив некуда, если приёмника нет вовсе (панель накрыта показом),
    // если он занят своим чтением или если он не умеет принимать содержимое.
    final target = context.target;
    return target != null && !target.busy && target.path.isNotEmpty && target.source.canReceive;
  }

  /// Что паковать: помеченное, а без пометки — то, что под курсором.
  List<FileEntry> _sourcesOf(CommandContext context) => [
    for (final entry in context.targets)
      if (!entry.isParent) entry,
  ];

  /// Упаковать — или сперва спросить, как назвать и как жать.
  ///
  /// Имя задают либо параметром, либо человеком в окне. Первый случай идёт
  /// мимо окна вовсе; во втором команда показывает окно и уходит.
  @override
  Future<void> execute(CommandContext context) async {
    final target = context.target;
    if (_sourcesOf(context).isEmpty || target == null) {
      return;
    }

    Future<void> pack(String typed, ZipCompression compression, bool followLinks, [FcAsyncRun? run]) async {
      final name = _withExtension(typed);
      if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
        throw FsError(name, FsErrorKind.invalidName);
      }

      // Аренда обоих концов и проверка занятого имени — дело ядра: там живут
      // узлы, и там же идёт работа.
      final spec = OperationSpec(
        kind: ZipPacking.kind,
        targets: Targets.marked(context.panel.id),
        destination: target.id,
        options: {
          ZipPacking.nameOption: name,
          ZipPacking.compressionOption: compression.name,
          ZipPacking.followLinksOption: followLinks,
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
        ZipCompression.byName(context.invocation.param<String>(compressionParam)),
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
  /// называется «create zip archive».
  static String _withExtension(String raw) {
    final typed = raw.trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.zip') ? typed : '$typed.zip';
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
      return '${sources.single.name}.zip';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name.zip';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String destinationPathOf(CommandContext context) => context.target?.directory?.pathString ?? '';
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

  /// Ссылки: по умолчанию ложатся в архив ссылками, как в mc.
  bool followLinks = false;

  ZipCompression compression = ZipCompression.normal;

  void setFollowLinks(bool value) {
    followLinks = value;
    notifyListeners();
  }

  void setCompression(ZipCompression value) {
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
            hintText: 'archive.zip',
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
          child: FcSelect<ZipCompression>(
            options: {for (final value in ZipCompression.values) value: value.title},
            value: run.compression,
            onChanged: run.setCompression,
          ),
        ),
      ],
    );
  }
}

/// Что не так со ссылкой.
