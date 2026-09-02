import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

import 'archive_output.dart';
import 'tar_format.dart';
import 'tar_writer.dart';

/// Упаковка tar — работа ядра.
///
/// Живёт там, где источники: обходит дерево, читает байты и отдаёт готовый
/// архив приёмнику. Команда её только называет и приносит доводы заявкой
/// (`docs/spec/client-server.md`, §5.4).
class TarPacking {
  TarPacking({required StagingArea staging}) : _staging = staging;

  /// Имя работы: под ним её и зовут из команды.
  static const String kind = 'tar.pack';

  static const String nameOption = 'name';
  static const String formatOption = 'format';
  static const String followLinksOption = 'followLinks';

  final StagingArea _staging;

  /// Молча затирать существующий архив нельзя: имя правят в окне и повторяют.
  static Future<void> _checkNameIsFree(DirectoryNode destination, String name) async {
    final provider = destination.provider;
    if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
      throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
    }
  }

  /// Упаковка: сборка архива во временном файле и передача его приёмнику.
  ///
  /// Через временный файл, а не прямо в приёмник: размер архива до конца работы
  /// неизвестен, а приёмник вправе его требовать. Прерванная работа при этом не
  /// оставляет полуархива на месте назначения.
  ///
  /// Сжатие идёт **в один проход**: gzip навешивается на тот же поток, которым
  /// собирается tar, и промежуточного несжатого файла не появляется.
  Operation<OperationInputs, void> operation() {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final params = TarPackParams.of(inputs);
      await _checkNameIsFree(params.destination, params.name);
      final sources = params.sources;
      final destination = params.destination;
      final progress = TransferProgress(op);
      // Плечи: сперва архив собирается, потом уходит приёмнику. Второе бывает
      // и дольше первого — по сети, например.
      progress.beginStage('packing', index: 1, count: 2);
      // Считаем рядом с работой, а не перед ней: обойти дерево стоит почти
      // столько же, сколько его упаковать.
      unawaited(_count(sources, progress));

      final staged = await _staging.open('flex_commander_tar_create');
      final archivePath = p.join(staged.path, params.name);
      int? entryItem;

      try {
        final items = _itemsOf(sources, op, progress, followLinks: params.followLinks);
        final bytes = writeTarStream(
          items,
          checkpoint: op.checkpoint,
          onEntry: (item) {
            progress.startSource(_sourceOf(item.name));
            entryItem = progress.startItem(item.name, bytes: item.size);
          },
          // Байты приходят по мере того, как читается запись: так видно
          // движение и внутри одного большого файла, а не только между ними.
          onBytes: (count) => progress.advanceBytes(count, entryItem),
        );

        final out = params.format.compressed ? gzip.encoder.bind(bytes) : bytes;
        final sink = File(archivePath).openWrite();
        try {
          await sink.addStream(out);
        } finally {
          await sink.close();
        }

        await op.checkpoint();

        // Второе плечо: готовый архив уходит приёмнику. Его размер до этого
        // момента неизвестен, поэтому работа прирастает здесь — бар при этом не
        // прыгает назад, а лишь пересчитывает оставшееся.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        progress.beginStage('storing archive', index: 2, count: 2);
        await deliverArchive(archivePath, destination, params.name, op, progress);
      } finally {
        progress.stop();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Записи архива — потоком, по мере обхода дерева.
  ///
  /// Потоком, а не списком: содержимое каждой записи читается прямо из своего
  /// провайдера в тот момент, когда её пишут. Ни временных копий, ни памяти под
  /// файл — tar пишется подряд, и держать в руках нечего.
  Stream<TarItem> _itemsOf(
    List<FsNode> sources,
    TaskOperation<Object?, void> op,
    TransferProgress progress, {
    required bool followLinks,
  }) async* {
    for (final source in sources) {
      await op.checkpoint();
      progress.startSource(source.name);
      yield* _itemsOfNode(source, source.name, op, progress, followLinks: followLinks);
    }
  }

  Stream<TarItem> _itemsOfNode(
    FsNode node,
    String entryName,
    TaskOperation<Object?, void> op,
    TransferProgress progress, {
    required bool followLinks,
  }) async* {
    await op.checkpoint();

    // Ссылка разбирается до того, как узел сочтут файлом: ссылка на каталог
    // файлом не является, и поток по ней не открыть.
    if (node is LinkNode && !followLinks) {
      // Ссылкой — то, ради чего мир Unix и пользуется tar.
      yield TarItem.link(name: entryName, linkTarget: node.reference, modified: node.modified);
      progress.advance();
      return;
    }

    final resolved = node is LinkNode ? await node.resolve().run(node) ?? node : node;

    if (resolved is DirectoryNode) {
      yield TarItem.directory(name: '$entryName/', mode: _modeOf(resolved, 0x1ed), modified: resolved.modified);
      progress.advance();

      final children = await resolved.provider.listChildren(resolved);
      for (final child in children) {
        if (child is ParentDirNode) {
          continue;
        }
        yield* _itemsOfNode(child, '$entryName/${child.name}', op, progress, followLinks: followLinks);
      }
      return;
    }

    final provider = resolved.provider;
    if (provider is! FileContentProvider) {
      throw FsError(resolved.pathString, FsErrorKind.notSupported);
    }

    // Размер объявляется в заголовке **до** содержимого, поэтому он обязан
    // быть известен заранее. Источник, который его не знает (бывает у чужих
    // серверов), пришлось бы сперва вычитать целиком — а это отдельная цена, и
    // платить её молча неправильно.
    if (resolved.size < 0) {
      throw FsError(resolved.pathString, FsErrorKind.notSupported);
    }

    yield TarItem.file(
      name: entryName,
      size: resolved.size,
      mode: _modeOf(resolved, 0x1a4),
      modified: resolved is FileNode ? resolved.modified : null,
      content: await (provider as FileContentProvider).openRead(resolved),
    );
    progress.advance();
  }

  /// Права из источника; их нет — обычные для файла или каталога.
  static int _modeOf(FsNode node, int fallback) {
    final mode = node is FileNode ? node.attributes.mode : 0;
    return mode == 0 ? fallback : mode;
  }

  /// Первое звено пути записи — тот источник, из которого она пришла.
  static String _sourceOf(String entryName) {
    final slash = entryName.indexOf('/');
    return slash < 0 ? entryName : entryName.substring(0, slash);
  }

  /// Считает объекты и байты — рядом с работой, а не перед ней.
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
}

/// Что упаковать, куда и в каком виде.
class TarPackParams {
  factory TarPackParams.of(OperationInputs inputs) {
    final destination = inputs.destination;
    final name = inputs.option<String>(TarPacking.nameOption) ?? '';
    if (destination == null || name.isEmpty) {
      throw FsError(name, FsErrorKind.invalidName);
    }
    return TarPackParams(
      inputs.targets,
      destination,
      name,
      format: TarFormat.byName(inputs.option<String>(TarPacking.formatOption)),
      followLinks: inputs.option<bool>(TarPacking.followLinksOption) ?? false,
    );
  }

  const TarPackParams(
    this.sources,
    this.destination,
    this.name, {
    this.format = TarFormat.gzip,
    this.followLinks = false,
  });

  final List<FsNode> sources;
  final DirectoryNode destination;
  final String name;
  final TarFormat format;
  final bool followLinks;
}
