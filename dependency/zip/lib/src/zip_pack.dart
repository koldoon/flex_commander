import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 'zip_compression.dart';
import 'zip_encoding.dart';

/// Упаковка zip — работа ядра.
///
/// Живёт там, где источники: обходит дерево, читает байты и отдаёт готовый
/// архив приёмнику. Команда её только называет и приносит доводы заявкой
/// (`docs/spec/client-server.md`, §5.4).
class ZipPacking {
  ZipPacking({required StagingArea staging}) : _staging = staging;

  /// Имя работы: под ним её и зовут из команды.
  static const String kind = 'zip.pack';

  /// Доводы заявки.
  static const String nameOption = 'name';
  static const String compressionOption = 'compression';
  static const String followLinksOption = 'followLinks';

  final StagingArea _staging;

  /// Упаковка: сборка архива во временном файле и передача его приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник: zip дописывает оглавление в
  /// конец, и отданный наружу поток пришлось бы держать открытым до последнего
  /// байта — а приёмник вправе и не уметь такого. Прерванная работа при этом не
  /// оставляет полуархива на месте назначения.
  /// Молча затирать существующий архив нельзя: имя можно поправить прямо в
  /// окне и повторить.
  ///
  /// Проверяется здесь, а не в команде: спрашивать у каталога, что в нём
  /// лежит, умеет только та сторона, где он живёт. Отказ приходит до первого
  /// слова о ходе дела, и окно поэтому возвращается к форме.
  static Future<void> _checkNameIsFree(DirectoryNode destination, String name) async {
    final provider = destination.provider;
    if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
      throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
    }
  }

  Operation<OperationInputs, void> operation() {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final params = ZipPackParams.of(inputs);
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

      final links = _Links(follow: followLinks);

      final staged = await _staging.open('flex_commander_zip_create');
      final copies = LocalCopySession(_staging, prefix: 'flex_commander_zip_source');
      final archivePath = p.join(staged.path, name);

      try {
        // Сперва обход, потом сжатие — и сжатие в отдельном изоляте.
        //
        // Обход спрашивает провайдеров и человека (про ссылки), а это дело
        // главного изолята: туда не переехать. Зато сжатие туда переезжает
        // целиком — оно синхронное, и на большом дереве кадры не выходят вовсе.
        // Метка записи, которую упаковщик держит в работе: он идёт по одной,
        // но байты и её конец приходят разными вызовами.
        int? entryItem;

        final entries = <ZipItem>[];
        for (final source in sources) {
          await op.checkpoint();
          progress.startSource(source.name);
          // Объекты и байты считает сам обход: `sourceDoneWholly` здесь
          // добавил бы их второй раз — он для работ, которые проходят источник
          // целиком одним действием.
          await _addNode(entries, source, source.name, copies, op, progress, links);
        }

        await op.checkpoint();

        await encodeZipArchive(
          archivePath: archivePath,
          entries: entries,
          level: compression.level,
          op: op,
          onEntry: (name, bytes) {
            // Источник задания — тот, из которого запись пришла: он назван
            // первым звеном её пути. Строка `Item` держится на нём, пока по
            // его содержимому бежит `File`.
            progress.startSource(_sourceOf(name));
            entryItem = progress.startItem(name, bytes: bytes);
          },
          onEntryDone: (_) {
            if (entryItem != null) {
              progress.finishItem(entryItem!);
              entryItem = null;
            }
            progress.advance();
          },
          // Байты приходят по мере того, как упаковщик читает запись: так видно
          // движение и внутри одного большого файла, а не только между файлами.
          onBytes: (bytes) => progress.advanceBytes(bytes, entryItem),
        );

        await op.checkpoint();

        // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
        // момента неизвестен, поэтому работа прирастает здесь — бар при этом
        // не прыгает назад, а лишь пересчитывает оставшееся.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        progress.beginStage('storing archive', index: 2, count: 2);
        await _deliver(archivePath, destination, name, op, progress);
      } finally {
        progress.stop();
        await copies.purge();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Записывает один объект в список заданий: файл — записью, каталог —
  /// записью и обходом.
  ///
  /// Именно список, а не сам архив: сжатие идёт потом и в другом изоляте.
  Future<void> _addNode(
    List<ZipItem> entries,
    FsNode node,
    String entryName,
    LocalCopySession copies,
    TaskOperation<Object?, void> op,
    TransferProgress progress,
    _Links links,
  ) async {
    await op.checkpoint();

    // Ссылка разбирается до того, как узел сочтут файлом: ссылка на каталог
    // файлом не является, и поток по ней не открыть — на этом и падала
    // упаковка каталога с `.framework` внутри.
    if (node is LinkNode) {
      final FsNode? followed = await _addLink(node, op, links);
      if (followed == null) {
        return;
      }
      try {
        await _addNode(entries, followed, entryName, copies, op, progress, links);
      } finally {
        links.leaveLink(node);
      }
      return;
    }

    if (node is DirectoryNode) {
      // Пустой каталог иначе пропал бы: в zip он существует только записью.
      entries.add(ZipItem.directory(entryName));

      for (final child in await node.provider.listChildren(node)) {
        await _addNode(entries, child, '$entryName/${child.name}', copies, op, progress, links);
      }
      return;
    }

    // Настоящий путь берётся как есть, чужой источник выкладывается во
    // временный файл: упаковщику нужен файл, по которому можно ходить, — и
    // ходить он будет из другого изолята, где провайдеров нет вовсе.
    entries.add(ZipItem.file(entryName, await copies.localPathOf(node)));
  }

  /// Что делать со ссылкой: положить записью-ссылкой или пойти по ней.
  ///
  /// Возвращает цель, если решено идти; null — со ссылкой уже разобрались.
  Future<FsNode?> _addLink(LinkNode node, TaskOperation<Object?, void> op, _Links links) async {
    if (!links.follow) {
      // Ссылку в архив положить нечем.
      //
      // В zip она хранится файлом с правами UNIX (`S_IFLNK`) и признаком
      // «создано на UNIX» в заголовке. Библиотека `archive` пишет заголовок
      // всегда с признаком MS-DOS, поэтому такую запись не узнал бы даже её
      // собственный распаковщик. Подменять ссылку содержимым цели молча
      // нельзя — спрашиваем, как и при отказах.
      await _askAboutLink(op, node, links, kind: _LinkTrouble.cannotStore);
      return null;
    }

    if (!links.enterLink(node)) {
      // По этой ссылке мы уже идём выше по ветке: `docs/loop → docs`.
      await _askAboutLink(op, node, links, kind: _LinkTrouble.recursive);
      return null;
    }

    final FsNode? followed = await node.resolve().result;
    if (followed == null) {
      links.leaveLink(node);
      await _askAboutLink(op, node, links, kind: _LinkTrouble.broken);
      return null;
    }
    return followed;
  }

  /// Вопрос про ссылку — тот же, что при отказах.
  Future<void> _askAboutLink(
    TaskOperation<Object?, void> op,
    LinkNode node,
    _Links links, {
    required _LinkTrouble kind,
  }) async {
    if (links.skipAll) {
      return;
    }

    final answer = await op.ask(
      OperationRequest(
        message: switch (kind) {
          _LinkTrouble.cannotStore => 'Cannot store the link «${node.name}» in a zip archive',
          _LinkTrouble.recursive => 'The link «${node.name}» points into the directory being packed',
          _LinkTrouble.broken => 'The link «${node.name}» leads nowhere',
        },
        options: const [TransferAnswers.skip, TransferAnswers.skipAll, TransferAnswers.cancel],
        enterOption: TransferAnswers.skip,
      ),
    );

    if (answer == TransferAnswers.cancel) {
      throw const OperationCanceled();
    }
    if (answer == TransferAnswers.skipAll) {
      links.skipAll = true;
    }
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
    final sink = await (provider as FileContentReceiver).openWrite(destination, name, length: await file.length());

    try {
      progress.startSource(name);
      final item = progress.startItem(name, bytes: await file.length());
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
      // Второй проход по тем же байтам — такая же работа, как первый.
      progress.countBytes(bytes);
    }

    progress.countingFinished();
  }

  /// Источник, из которого пришла запись архива: первое звено её пути.
  ///
  /// Записи именуются от источника (`docs/nested/deep.txt`), и по имени видно,
  /// чей это объект, — упаковщику знать про источники незачем.
  String _sourceOf(String entry) {
    final cut = entry.indexOf('/');
    return cut < 0 ? entry : entry.substring(0, cut);
  }
}

/// Что делать со ссылками при упаковке.
///
/// Своя, а не общая с движком переноса: у движка вопрос «умеет ли приёмник
/// хранить ссылку», а zip умеет всегда — здесь решается только «класть ссылкой
/// или идти по ней».
class _Links {
  _Links({required this.follow});

  /// Дальше этого числа вложенных ссылок не идём: относительные ссылки могут
  /// ходить по кругу, ни разу не повторившись строкой.
  static const int maxDepth = 32;

  final bool follow;

  bool skipAll = false;

  /// Куда ведут ссылки, по которым мы сейчас идём.
  ///
  /// По цели, а не по пути: цель ссылки остаётся ребёнком самой ссылки, и путь
  /// у неё идёт через ссылку — сравнивать пути бесполезно.
  final Set<String> _following = {};

  bool enterLink(LinkNode node) {
    if (_following.length >= maxDepth) {
      return false;
    }
    return _following.add(node.reference);
  }

  void leaveLink(LinkNode node) => _following.remove(node.reference);
}

/// Что паковать, куда и как.
///
/// Собирается из заявки: цели и приёмник ядро уже развернуло, остальное лежит
/// доводами.
class ZipPackParams {
  const ZipPackParams(
    this.sources,
    this.destination,
    this.name, {
    required this.compression,
    required this.followLinks,
  });

  factory ZipPackParams.of(OperationInputs inputs) {
    final destination = inputs.destination;
    final name = inputs.option<String>(ZipPacking.nameOption) ?? '';
    if (destination == null || name.isEmpty) {
      throw FsError(name, FsErrorKind.invalidName);
    }
    return ZipPackParams(
      inputs.targets,
      destination,
      name,
      compression: ZipCompression.byName(inputs.option<String>(ZipPacking.compressionOption)),
      followLinks: inputs.option<bool>(ZipPacking.followLinksOption) ?? false,
    );
  }

  final List<FsNode> sources;

  /// Каталог, в котором появится архив.
  final DirectoryNode destination;

  /// Имя архива вместе с расширением: `notes.zip`.
  final String name;

  final ZipCompression compression;

  /// Идти ли по символическим ссылкам вместо того, чтобы класть их в архив
  /// ссылками.
  final bool followLinks;
}

enum _LinkTrouble { cannotStore, recursive, broken }
