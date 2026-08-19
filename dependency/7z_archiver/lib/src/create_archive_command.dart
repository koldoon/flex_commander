import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'seven_zip_cli.dart';

/// Степень сжатия — то немногое, что при упаковке действительно выбирают.
///
/// Уровни те же, что у формата: без сжатия хранит быстрее всего, лучшее жмёт
/// заметно дольше ради нескольких процентов. По умолчанию — среднее: так
/// делают все менеджеры, и почти всегда это правильный ответ.
enum SevenZipCompression {
  none('Store', 0),
  fast('Fast', 1),
  normal('Normal', 5),
  best('Best', 9);

  const SevenZipCompression(this.title, this.level);

  /// Название для пользователя.
  final String title;

  /// Уровень сжатия: 0 — без сжатия, 9 — самое плотное.
  final int level;

  static SevenZipCompression byName(String? name) =>
      values.firstWhere((value) => value.name == name, orElse: () => SevenZipCompression.normal);
}

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
class CreateSevenZipArchiveCommand extends AsyncCommandBase {
  CreateSevenZipArchiveCommand({required StagingArea staging, required SevenZipCli cli})
    : _staging = staging,
      _cli = cli;

  static const String commandId = '7z.create';

  /// Имя будущего архива.
  static const String nameParam = 'name';

  /// Степень сжатия — имя значения [SevenZipCompression].
  static const String compressionParam = 'compression';

  final StagingArea _staging;
  final SevenZipCli _cli;

  @override
  String get id => commandId;

  @override
  String get label => 'Create 7z archive';

  @override
  String get description => 'Pack the selected items into a new 7z archive';

  @override
  String get dialogTitle => 'Create 7z archive';

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
  /// называется «create 7z archive».
  String get _archiveName {
    final typed = (param<String>(nameParam) ?? '').trim();
    if (typed.isEmpty) {
      return '';
    }
    return typed.toLowerCase().endsWith('.7z') ? typed : '$typed.7z';
  }

  SevenZipCompression get _compression => SevenZipCompression.byName(param<String>(compressionParam));

  /// Упаковка.
  ///
  /// Если приёмник — настоящая файловая система, программа пишет архив прямо на
  /// место: лишнего плеча не появляется вовсе. Иначе архив собирается во
  /// временном файле и уходит приёмнику байтами — как у zip.
  AsyncOperation<void> _pack(List<FsNode> sources, DirectoryNode destination, String name) {
    return TaskOperation<void>((op) async {
      final progress = TransferProgress(op, 'Packing');
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final direct = destination.provider.capabilities.realFileSystem;
      final staged = await _staging.open('flex_commander_7z_create');
      final archivePath = direct ? p.join(destination.pathString, name) : p.join(staged.path, name);

      try {
        final workingDirectory = await _sourcesRoot(sources, staged, op, progress);

        await _run(archivePath, workingDirectory, [for (final source in sources) source.name], op, progress);
        await op.checkpoint();

        if (!direct) {
          // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
          // момента неизвестен, поэтому работа прирастает здесь — бар при этом
          // не прыгает назад, а лишь пересчитывает оставшееся.
          final packed = await File(archivePath).length();
          progress.countBytes(packed);
          await _deliver(archivePath, destination, name, op, progress);
        }
      } on Object {
        // Прерванная работа не должна оставить полуархив на месте назначения.
        if (direct) {
          await File(archivePath).delete().catchError((Object _) => File(archivePath));
        }
        rethrow;
      } finally {
        progress.stop();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Каталог, относительно которого программа увидит источники.
  ///
  /// У источников с настоящими путями это каталог самой панели: имена уйдут
  /// относительными, и записи в архиве получатся такими же. У остальных —
  /// временный каталог, куда содержимое приходится выложить: программа умеет
  /// упаковывать только то, что лежит на диске.
  Future<String> _sourcesRoot(
    List<FsNode> sources,
    StagedDirectory staged,
    TaskOperation<void> op,
    TransferProgress progress,
  ) async {
    final provider = sources.first.provider;
    if (provider.capabilities.realFileSystem) {
      final directory = sources.first.parentDirectory;
      if (directory != null) {
        return provider.pathOf(directory);
      }
    }

    final root = p.join(staged.path, 'sources');
    await Directory(root).create(recursive: true);

    for (final source in sources) {
      await _materialize(source, p.join(root, source.name), op, progress);
    }
    return root;
  }

  /// Выкладывает узел на диск: файл — байтами, каталог — обходом.
  Future<void> _materialize(FsNode node, String path, TaskOperation<void> op, TransferProgress progress) async {
    await op.checkpoint();

    if (node is DirectoryNode) {
      await Directory(path).create(recursive: true);
      for (final child in await node.provider.listChildren(node)) {
        await _materialize(child, p.join(path, child.name), op, progress);
      }
      return;
    }

    final provider = node.provider;
    if (provider is! FileContentProvider) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    // Выкладывание — это работа сверх упаковки: те же байты пройдут ещё раз.
    // Общий объём растёт здесь, чтобы бар не показывал больше сделанного, чем
    // есть на самом деле.
    progress
      ..countBytes(node.size < 0 ? 0 : node.size)
      ..startItem(node.name, bytes: node.size < 0 ? null : node.size);

    final file = File(path);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    try {
      await sink.addStream(
        (await (provider as FileContentProvider).openRead(node)).asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length);
          return chunk;
        }),
      );
    } finally {
      await sink.close();
    }
  }

  /// Зовёт программу и переводит её вывод в ход работы.
  ///
  /// Программа рассказывает о себе строками вида `+ docs/readme.txt` и
  /// ` 42% 7 + docs/readme.txt`. Ни та, ни другая не говорят, сколько байт уже
  /// сжато внутри записи, — поэтому полоса текущего объекта шагает по файлу
  /// целиком. Придумывать движение внутри записи было бы враньём.
  ///
  /// Вывод читается отдельно от ожидания конца: отмену нельзя ставить в
  /// зависимость от того, разговорчива ли программа. Большой файл она жмёт
  /// молча минутами, и всё это время Esc должен работать.
  Future<void> _run(
    String archivePath,
    String workingDirectory,
    List<String> names,
    TaskOperation<void> op,
    TransferProgress progress,
  ) async {
    final session = await _cli.start([
      'a',
      '-t7z',
      '-mx=${_compression.level}',
      // Имена обработанных записей и проценты — то единственное, из чего можно
      // собрать ход работы.
      '-bb1',
      '-bsp1',
      '-bso1',
      ..._cli.literalNames,
      '--',
      archivePath,
      ...names,
    ], workingDirectory: workingDirectory);

    final complaints = StringBuffer();
    final watching = session.stderr.transform(const Utf8Decoder(allowMalformed: true)).forEach(complaints.write);

    final packing = _PackingProgress(progress, workingDirectory);
    final reading = _read(session.stdout, packing).catchError((Object _) {});

    try {
      final exit = session.exitCode;
      var finished = false;
      unawaited(exit.then((_) => finished = true));

      // Опрос, а не ожидание: `checkpoint` — единственное место, где отмена
      // превращается в вопрос пользователю, и звать его нужно самим.
      while (!finished) {
        await Future.any([exit, Future<void>.delayed(_cancelPollInterval)]);
        if (finished) {
          break;
        }
        await op.checkpoint();
      }

      final code = await exit;
      await reading;
      await watching;

      if (!_cli.succeeded(code)) {
        throw SevenZipCli.errorOf(archivePath, code, complaints.toString());
      }

      packing.finish();
    } finally {
      // Отмена или ошибка: программа, оставшаяся без слушателя, должна
      // остановиться, а не дописывать архив в никуда.
      await session.kill();
      await reading;
    }
  }

  /// Как часто спрашивать, не передумал ли пользователь.
  static const Duration _cancelPollInterval = Duration(milliseconds: 200);

  Future<void> _read(Stream<List<int>> output, _PackingProgress packing) async {
    await for (final line in _lines(output)) {
      final item = sevenZipItemOf(line);
      if (item != null) {
        await packing.startItem(item);
      }
    }
  }

  /// Строки вывода. Ход работы программа печатает через возврат каретки, а не
  /// перевод строки: без разбиения по обоим она выглядела бы одной строкой на
  /// весь архив.
  Stream<String> _lines(Stream<List<int>> source) {
    return source
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .expand((line) => line.split('\r'));
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
    final length = await file.length();
    final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: length);

    try {
      progress
        ..startSource(name)
        ..startItem(name, bytes: length);
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
      return '${sources.single.name}.7z';
    }
    final directory = context.panel.directory;
    final name = directory == null || directory.name == '/' ? 'archive' : directory.name;
    return '$name.7z';
  }

  /// Куда ляжет архив — показывается в окне, чтобы «в какую панель» не
  /// приходилось угадывать.
  String get destinationPath => context.target.directory?.pathString ?? '';
}

/// Ход упаковки: какая запись сейчас в работе и сколько она весит.
///
/// Программа называет запись, когда берётся за неё, — значит, приход имени
/// означает, что предыдущая запись готова. Последняя закрывается уже по концу
/// работы.
class _PackingProgress {
  _PackingProgress(this._progress, this._workingDirectory);

  final TransferProgress _progress;
  final String _workingDirectory;

  String? _current;
  int _bytes = 0;

  Future<void> startItem(String name) async {
    if (name == _current) {
      return;
    }
    finish();

    _current = name;
    // Размер берётся с диска: программа его не печатает, а один вызов stat
    // рядом со сжатием ничего не стоит.
    _bytes = await _sizeOf(p.join(_workingDirectory, name));
    _progress.startItem(p.basename(name), bytes: _bytes);
  }

  /// Закрывает текущую запись: объект готов, байты засчитаны.
  void finish() {
    final current = _current;
    if (current == null) {
      return;
    }
    _progress
      ..advanceBytes(_bytes)
      ..advance(p.basename(current));
    _current = null;
    _bytes = 0;
  }

  /// Размер файла на диске; 0 — его нет (каталог, пропавший файл).
  Future<int> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }
}

/// Имя записи из строки вывода программы.
///
/// Программа говорит о работе двумя видами строк: `+ docs/readme.txt` при
/// `-bb1` и ` 42% 7 + docs/readme.txt` при `-bsp1`. Имя в них лежит одинаково,
/// поэтому разбор один — и ход работы виден даже там, где какой-то из двух
/// ключей не поддержан.
String? sevenZipItemOf(String line) {
  final match = RegExp(r'(?:^|\s)[+UT=]\s+(\S.*)$').firstMatch(line.trimRight());
  final name = match?.group(1);
  return name == null || name.isEmpty ? null : name;
}

/// Форма создания архива: имя и степень сжатия.
class _CreateArchiveForm extends StatefulWidget {
  const _CreateArchiveForm({required this.command});

  final CreateSevenZipArchiveCommand command;

  @override
  State<_CreateArchiveForm> createState() => _CreateArchiveFormState();
}

class _CreateArchiveFormState extends State<_CreateArchiveForm> {
  late final TextEditingController _name = TextEditingController(text: widget.command.defaultName);
  late final TextEditingController _destination = TextEditingController(text: widget.command.destinationPath);
  SevenZipCompression _compression = SevenZipCompression.normal;

  @override
  void initState() {
    super.initState();
    // Значения задаются сразу, а не при подтверждении: Enter обрабатывает
    // ядро, и к моменту execute параметры уже должны быть на месте.
    widget.command.setParam(CreateSevenZipArchiveCommand.nameParam, _name.text);
    widget.command.setParam(CreateSevenZipArchiveCommand.compressionParam, _compression.name);
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
              hintText: 'archive.7z',
              onChanged: (value) => widget.command.setParam(CreateSevenZipArchiveCommand.nameParam, value),
              onSubmitted: (_) => widget.command.submit(),
            ),
          ),
          SizedBox(height: metrics.dialogGap),
          CommandDialogField(
            label: 'Compression',
            child: FcRadioGroup<SevenZipCompression>(
              direction: Axis.horizontal,
              options: {for (final value in SevenZipCompression.values) value: value.title},
              value: _compression,
              onChanged: (value) {
                setState(() => _compression = value);
                widget.command.setParam(CreateSevenZipArchiveCommand.compressionParam, value.name);
              },
            ),
          ),
        ],
      ),
    );
  }
}
