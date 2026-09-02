import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 'seven_zip_cli.dart';
import 'seven_zip_compression.dart';

/// Упаковка 7z — работа ядра.
///
/// Живёт там, где источники: обходит дерево, зовёт программу и отдаёт готовый
/// архив приёмнику. Команда её только называет и приносит доводы заявкой
/// (`docs/spec/client-server.md`, §5.4).
class SevenZipPacking {
  SevenZipPacking({required StagingArea staging, required SevenZipCli cli}) : _staging = staging, _cli = cli;

  /// Имя работы: под ним её и зовут из команды.
  static const String kind = '7z.pack';

  static const String nameOption = 'name';
  static const String compressionOption = 'compression';
  static const String followLinksOption = 'followLinks';

  final StagingArea _staging;
  final SevenZipCli _cli;

  /// Молча затирать существующий архив нельзя: имя правят в окне и повторяют.
  static Future<void> _checkNameIsFree(DirectoryNode destination, String name) async {
    final provider = destination.provider;
    if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
      throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
    }
  }

  /// Упаковка.
  ///
  /// Если приёмник — настоящая файловая система, программа пишет архив прямо на
  /// место: лишнего плеча не появляется вовсе. Иначе архив собирается во
  /// временном файле и уходит приёмнику байтами — как у zip.
  Operation<OperationInputs, void> operation() {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final params = SevenZipPackParams.of(inputs);
      await _checkNameIsFree(params.destination, params.name);
      final sources = params.sources;
      final destination = params.destination;
      final name = params.name;
      final compression = params.compression;
      final followLinks = params.followLinks;
      final progress = TransferProgress(op);
      // Плечи: сперва архив собирается, потом уходит приёмнику. Второе
      // бывает и дольше первого — по сети, например.
      progress.beginStage('packing', index: 1, count: 2);
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final direct = destination.provider.capabilities.realFileSystem;
      final staged = await _staging.open('flex_commander_7z_create');
      final archivePath = direct ? p.join(destination.pathString, name) : p.join(staged.path, name);

      try {
        final workingDirectory = await _sourcesRoot(sources, staged, op, progress);

        // Имена уходят списком, а не аргументами: помеченных может быть
        // тысячи, и командная строка такой длины не бывает.
        final list = File(p.join(staged.path, 'sources.txt'));
        await list.writeAsString(sources.map((source) => source.name).join('\n'), encoding: utf8);

        await _run(
          archivePath,
          workingDirectory,
          list.path,
          op,
          progress,
          compression: compression,
          followLinks: followLinks,
        );
        await op.checkpoint();

        if (!direct) {
          // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
          // момента неизвестен, поэтому работа прирастает здесь — бар при этом
          // не прыгает назад, а лишь пересчитывает оставшееся.
          final packed = await File(archivePath).length();
          progress
            ..countBytes(packed)
            ..beginStage('storing archive', index: 2, count: 2);
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
    TaskOperation<Object?, void> op,
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
  Future<void> _materialize(
    FsNode node,
    String path,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
  ) async {
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
    progress.countBytes(node.size < 0 ? 0 : node.size);
    final item = progress.startItem(node.name, bytes: node.size < 0 ? null : node.size);

    final file = File(path);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    try {
      await sink.addStream(
        (await (provider as FileContentProvider).openRead(node)).asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length, item);
          return chunk;
        }),
      );
    } finally {
      progress.finishItem(item);
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
    String listFile,
    TaskOperation<Object?, void> op,
    TransferProgress progress, {
    required SevenZipCompression compression,
    required bool followLinks,
  }) async {
    final session = await _cli.start([
      'a',
      '-t7z',
      '-mx=${compression.level}',
      '-scsUTF-8',
      // Без него `7z` кладёт в архив содержимое цели вместо самой ссылки.
      if (!followLinks) '-snl',
      SevenZipCli.listSwitch(listFile),
      // Имена обработанных записей и проценты — то единственное, из чего можно
      // собрать ход работы.
      '-bb1',
      '-bsp1',
      '-bso1',
      ..._cli.literalNames,
      '--',
      archivePath,
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
    TaskOperation<Object?, void> op,
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
      progress.startSource(name);
      final item = progress.startItem(name, bytes: length);
      await sink.addStream(
        file.openRead().asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length, item);
          return chunk;
        }),
      );
      await sink.close();
      progress.finishItem(item);
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
  int? _item;
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
    // Источник задания — тот, из которого запись пришла: он назван первым
    // звеном её пути. Строка `Item` держится на нём, пока по его содержимому
    // бежит `File`.
    final cut = name.indexOf('/');
    _progress.startSource(cut < 0 ? name : name.substring(0, cut));
    _item = _progress.startItem(p.basename(name), bytes: _bytes);
  }

  /// Закрывает текущую запись: объект готов, байты засчитаны.
  void finish() {
    final current = _current;
    if (current == null) {
      return;
    }
    _progress.advanceBytes(_bytes, _item);
    if (_item case final item?) {
      _progress.finishItem(item);
    }
    _progress.advance();
    _current = null;
    _item = null;
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

/// Что паковать, куда и как.
class SevenZipPackParams {
  factory SevenZipPackParams.of(OperationInputs inputs) {
    final destination = inputs.destination;
    final name = inputs.option<String>(SevenZipPacking.nameOption) ?? '';
    if (destination == null || name.isEmpty) {
      throw FsError(name, FsErrorKind.invalidName);
    }
    return SevenZipPackParams(
      inputs.targets,
      destination,
      name,
      compression: SevenZipCompression.byName(inputs.option<String>(SevenZipPacking.compressionOption)),
      followLinks: inputs.option<bool>(SevenZipPacking.followLinksOption) ?? false,
    );
  }

  const SevenZipPackParams(
    this.sources,
    this.destination,
    this.name, {
    required this.compression,
    required this.followLinks,
  });

  final List<FsNode> sources;

  /// Каталог, в котором появится архив.
  final DirectoryNode destination;

  /// Имя архива вместе с расширением: `notes.7z`.
  final String name;

  final SevenZipCompression compression;

  /// Идти ли по символическим ссылкам вместо того, чтобы класть их в архив
  /// ссылками.
  final bool followLinks;
}

/// Программа говорит о работе двумя видами строк: `+ docs/readme.txt` при
/// `-bb1` и ` 42% 7 + docs/readme.txt` при `-bsp1`. Имя в них лежит одинаково,
/// поэтому разбор один — и ход работы виден даже там, где какой-то из двух
/// ключей не поддержан.
String? sevenZipItemOf(String line) {
  final match = RegExp(r'(?:^|\s)[+UT=]\s+(\S.*)$').firstMatch(line.trimRight());
  final name = match?.group(1);
  return name == null || name.isEmpty ? null : name;
}
