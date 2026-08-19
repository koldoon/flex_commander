import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'counting_input_stream.dart';

/// Степень сжатия — то немногое, что при упаковке действительно выбирают.
///
/// Уровни те же, что у формата: без сжатия хранит быстрее всего, лучшее жмёт
/// заметно дольше ради нескольких процентов. По умолчанию — среднее: так
/// делают все менеджеры, и почти всегда это правильный ответ.
enum ZipCompression {
  none('Store', 0),
  fast('Fast', 1),
  normal('Normal', 6),
  best('Best', 9);

  const ZipCompression(this.title, this.level);

  /// Название для пользователя.
  final String title;

  /// Уровень deflate: 0 — без сжатия, 9 — самое плотное.
  final int level;

  static ZipCompression byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => ZipCompression.normal);
}

/// Упаковать выбранное в новый zip-архив.
///
/// Архив кладётся в каталог **пассивной** панели — туда же, куда копирует `F5`:
/// панель-источник и панель-приёмник у файлового менеджера всегда одни и те же,
/// какой бы ни была команда.
///
/// Источники могут лежать где угодно, в том числе в другом архиве: содержимое
/// берётся через [LocalCopySession], а она сама решает, есть ли у файла
/// настоящий путь или его придётся выложить во временный.
class CreateZipArchiveCommand extends AsyncCommandBase {
  CreateZipArchiveCommand({required StagingArea staging}) : _staging = staging;

  static const String commandId = 'zip.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Степень сжатия — имя значения [ZipCompression].
  static const String compressionParam = 'compression';

  final StagingArea _staging;

  @override
  String get id => commandId;

  @override
  String get label => 'Create archive';

  @override
  String get description => 'Pack the selected items into a new zip archive';

  @override
  String get dialogTitle => 'Create ZIP archive';

  /// Окно начинается с формы, и фокус нужен полю имени.
  @override
  bool get dialogTakesFocus => true;

  @override
  bool isExecutable(CommandContext context) {
    if (context.panel.busy || _sourcesOf(context).isEmpty) {
      return false;
    }
    // Класть архив некуда, если приёмник не умеет принимать содержимое.
    final destination = context.target.directory;
    return destination != null && destination.provider.canReceive;
  }

  List<FsNode> _sourcesOf(CommandContext context) => context.targets.where((node) => node is! ParentDirNode).toList();

  @override
  Future<void> execute() async {
    final sources = _sourcesOf(context);
    final destination = context.target.directory;
    if (sources.isEmpty || destination == null || isRunning) {
      return;
    }

    final name = _archiveName;
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
      throw FsError(name, FsErrorKind.invalidName);
    }

    final provider = destination.provider;
    if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
      // Молча затирать существующий архив нельзя: имя можно поправить прямо
      // в окне и повторить.
      throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
    }

    await runOperation(_pack(sources, destination, name), message: 'Packing…');

    // Приёмник теперь показывает не то, что на диске: там появился архив.
    await context.target.reload();
  }

  /// Имя архива: пустое расширение дописывается само — команда всё-таки
  /// называется «create zip archive».
  String get _archiveName {
    final typed = (param<String>(nameParam) ?? '').trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.zip') ? typed : '$typed.zip';
  }

  ZipCompression get _compression => ZipCompression.byName(param<String>(compressionParam));

  /// Упаковка: сборка архива во временном файле и передача его приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник: zip дописывает оглавление в
  /// конец, и отданный наружу поток пришлось бы держать открытым до последнего
  /// байта — а приёмник вправе и не уметь такого. Прерванная работа при этом не
  /// оставляет полуархива на месте назначения.
  AsyncOperation<void> _pack(List<FsNode> sources, DirectoryNode destination, String name) {
    return TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Packing');
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final staged = await _staging.open('flex_commander_zip_create');
      final copies = LocalCopySession(_staging, prefix: 'flex_commander_zip_source');
      final archivePath = p.join(staged.path, name);

      try {
        final output = OutputFileStream(archivePath);
        final encoder = ZipEncoder()..startEncode(output, level: _compression.level);
        final opened = <InputFileStream>[];

        try {
          for (final source in sources) {
            await op.checkpoint();
            progress.startSource(source.name);
            // Объекты и байты считает сам обход: `sourceDoneWholly` здесь
            // добавил бы их второй раз — он для работ, которые проходят
            // источник целиком одним действием.
            await _addNode(encoder, source, source.name, copies, opened, op, progress);
          }
          encoder.endEncode();
        } finally {
          await output.close();
          for (final stream in opened) {
            await stream.close();
          }
        }

        await op.checkpoint();

        // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
        // момента неизвестен, поэтому работа прирастает здесь — бар при этом
        // не прыгает назад, а лишь пересчитывает оставшееся.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        await _deliver(archivePath, destination, name, op, progress);
      } finally {
        progress.stop();
        await copies.purge();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Кладёт один объект в архив: файл — записью, каталог — записью и обходом.
  Future<void> _addNode(
    ZipEncoder encoder,
    FsNode node,
    String entryName,
    LocalCopySession copies,
    List<InputFileStream> opened,
    TaskOperation<void> op,
    TransferProgress progress,
  ) async {
    await op.checkpoint();

    if (node is DirectoryNode) {
      // Пустой каталог иначе пропал бы: в zip он существует только записью.
      encoder.add(ArchiveFile.directory('$entryName/'));
      progress.advance(node.name);

      for (final child in await node.provider.listChildren(node)) {
        await _addNode(encoder, child, '$entryName/${child.name}', copies, opened, op, progress);
      }
      return;
    }

    // Дважды: упаковщик читает запись ради контрольной суммы, а потом ради
    // сжатия — и второй проход занимает куда больше времени.
    progress.startItem(node.name, bytes: node.size < 0 ? null : node.size * 2);

    // Настоящий путь берётся как есть, чужой источник выкладывается во
    // временный файл: упаковщику нужен файл, по которому можно ходить.
    final path = await copies.localPathOf(node);
    final content = InputFileStream(path);
    opened.add(content);

    // Байты приходят по мере того, как упаковщик читает запись: так видно
    // движение и внутри одного большого файла, а не только между файлами.
    encoder.add(ArchiveFile.stream(entryName, CountingInputStream(content, progress.advanceBytes)));
    progress.advance(node.name);
  }

  /// Передаёт готовый архив приёмнику — тем же байтовым контрактом, которым
  /// пользуется движок переноса.
  Future<void> _deliver(
    String archivePath,
    DirectoryNode destination,
    String name,
    TaskOperation<void> op,
    TransferProgress progress,
  ) async {
    final provider = destination.provider;
    if (provider is! FileContentReceiver) {
      throw FsError(destination.pathString, FsErrorKind.notSupported);
    }

    final file = File(archivePath);
    final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: await file.length());

    try {
      progress
        ..startSource(name)
        ..startItem(name, bytes: await file.length());
      await sink.addStream(
        file.openRead().asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length);
          return chunk;
        }),
      );
      await sink.close();
    } on Object {
      await sink.close().catchError((Object _) {});
      rethrow;
    }
  }

  Future<void> _count(List<FsNode> sources, TransferProgress progress) async {
    for (var i = 0; i < sources.length; i++) {
      if (progress.stopped) {
        return;
      }

      var counted = 0;
      var bytes = 0;
      try {
        await sources[i].provider.countEntries(sources[i], (size) {
          counted++;
          bytes += size;
          progress.countOne(size);
        });
      } on FsError {
        // Каталог мог исчезнуть или оказаться закрытым — считаем дальше.
      }
      progress.sourceCounted(i, counted, bytes);
      // Второй проход по тем же байтам — такая же работа, как первый.
      progress.countBytes(bytes);
    }

    progress.countingFinished();
  }

  // --- окно ---

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: (context, _) {
        final question = this.question;
        if (question != null) {
          return CommandDialogQuestion(request: question, onAnswer: answer, onTextChanged: setAnswerText);
        }
        if (isRunning) {
          // То же окно хода работы, что у копирования: упаковка — такая же
          // длительная работа, и рассказывать о ней иначе незачем.
          return CommandDialogProgress(
            progress: progress,
            message: progressMessage,
            processed: processed,
            total: total,
            totalIsFinal: totalIsFinal,
            bytes: bytes,
            totalBytes: totalBytes,
            bytesPerSecond: bytesPerSecond,
            remaining: remaining,
            itemName: itemName,
            itemProgress: itemProgress,
            itemBytes: itemBytes,
            itemTotalBytes: itemTotalBytes,
            onCancel: cancel,
            onBackground: sendToBackground,
          );
        }

        return _CreateArchiveForm(command: this);
      },
    );
  }

  /// Имя, предложенное по умолчанию: по единственному объекту или по каталогу,
  /// из которого пакуем, — как в референсных менеджерах.
  String get defaultName {
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
  String get destinationPath => context.target.directory?.pathString ?? '';
}

/// Форма создания архива: имя и степень сжатия.
class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.command});

  final CreateZipArchiveCommand command;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  late final TextEditingController _name = TextEditingController(text: widget.command.defaultName);
  late final TextEditingController _destination = TextEditingController(text: widget.command.destinationPath);
  ZipCompression _compression = ZipCompression.normal;

  @override
  void initState() {
    super.initState();
    // Значения задаются сразу, а не при подтверждении: Enter обрабатывает
    // ядро, и к моменту execute параметры уже должны быть на месте.
    widget.command.setParam(CreateZipArchiveCommand.nameParam, _name.text);
    widget.command.setParam(CreateZipArchiveCommand.compressionParam, _compression.name);
  }

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;

    return CommandDialogForm(
      error: widget.command.error,
      onCancel: widget.command.dismiss,
      onSubmit: widget.command.submit,
      submitLabel: 'Create',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommandDialogField(label: 'Create in', child: FcTextField(controller: _destination, enabled: false)),
          SizedBox(height: metrics.dialogGap),
          CommandDialogField(
            label: 'Archive name',
            child: FcTextField(
              controller: _name,
              autofocus: true,
              hintText: 'archive.zip',
              onChanged: (value) => widget.command.setParam(CreateZipArchiveCommand.nameParam, value),
              onSubmitted: (_) => widget.command.submit(),
            ),
          ),
          SizedBox(height: metrics.dialogGap),
          CommandDialogField(
            label: 'Compression',
            child: FcRadioGroup<ZipCompression>(
              direction: Axis.horizontal,
              options: {for (final value in ZipCompression.values) value: value.title},
              value: _compression,
              onChanged: (value) {
                setState(() => _compression = value);
                widget.command.setParam(CreateZipArchiveCommand.compressionParam, value.name);
              },
            ),
          ),
        ],
      ),
    );
  }
}
