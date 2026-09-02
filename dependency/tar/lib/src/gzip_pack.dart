import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'package:path/path.dart' as p;

import 'archive_output.dart';

/// Сжатие одного файла в gz — работа ядра.
///
/// Отдельно от упаковки tar, и не ради симметрии: gzip жмёт **поток**, а не
/// набор файлов, и «сложить три файла в один .gz» — просьба, которую формат не
/// выполняет.
class GzipPacking {
  GzipPacking({required StagingArea staging}) : _staging = staging;

  /// Имя работы: под ним её и зовут из команды.
  static const String kind = 'tar.gzip';

  static const String nameOption = 'name';

  final StagingArea _staging;

  /// Молча затирать существующий файл нельзя: имя правится тут же в окне.
  static Future<void> _checkNameIsFree(DirectoryNode destination, String name) async {
    final provider = destination.provider;
    if (provider is NodeEditor && await (provider as NodeEditor).lookup(destination, name) != null) {
      throw FsError('${destination.pathString}/$name', FsErrorKind.alreadyExists);
    }
  }

  /// знать размер заранее.
  Operation<OperationInputs, void> operation() {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final params = GzipPackParams.of(inputs);
      await _checkNameIsFree(params.destination, params.name);
      final destination = params.destination;
      final progress = TransferProgress(op);
      progress.beginStage('compressing', index: 1, count: 2);

      final source = await _fileOf(params.source);
      final provider = source.provider;
      if (provider is! FileContentProvider) {
        throw FsError(source.pathString, FsErrorKind.notSupported);
      }

      // Объект здесь ровно один, и считать нечего: размер известен сразу.
      // Неизвестен он бывает у файла на сервере, который о нём не сказал, — и
      // тогда полоса идёт по байтам, а доли не показывает.
      progress.countOne(source.size);
      progress.countingFinished();

      final staged = await _staging.open('flex_commander_gz_create');
      final archivePath = p.join(staged.path, params.name);

      try {
        progress.startSource(source.name);
        final item = progress.startItem(source.name, bytes: source.size);

        final bytes = (await (provider as FileContentProvider).openRead(source)).asyncMap((chunk) async {
          await op.checkpoint();
          progress.advanceBytes(chunk.length, item);
          return chunk;
        });

        final sink = File(archivePath).openWrite();
        try {
          await sink.addStream(gzip.encoder.bind(bytes));
        } finally {
          await sink.close();
        }
        progress.finishItem(item);

        await op.checkpoint();

        // Второе плечо: сжатые байты уходят приёмнику. Их количество до этого
        // момента неизвестно, поэтому работа прирастает здесь.
        final packed = await File(archivePath).length();
        progress.countBytes(packed);
        progress.beginStage('storing file', index: 2, count: 2);
        await deliverArchive(archivePath, destination, params.name, op, progress);
      } finally {
        progress.stop();
        await staged.dispose();
      }

      progress.finish();
    });
  }

  /// Файл, который сжимаем: ссылку разбираем, каталог отвергаем.
  ///
  /// Каталог сюда доходит только вызовом со значением, мимо окна: команда без
  /// параметра его не предлагает вовсе. Но соврать всё равно нельзя — каталог в
  /// `.gz` не кладётся ни при каком способе вызова.
  static Future<FsNode> _fileOf(FsNode source) async {
    final resolved = source is LinkNode ? await source.resolve().run(source) ?? source : source;
    if (resolved is DirectoryNode) {
      throw FsError(resolved.pathString, FsErrorKind.notSupported);
    }
    return resolved;
  }
}

/// Что сжать, куда и под каким именем.
class GzipPackParams {
  factory GzipPackParams.of(OperationInputs inputs) {
    final destination = inputs.destination;
    final source = inputs.targets.singleOrNull;
    final name = inputs.option<String>(GzipPacking.nameOption) ?? '';
    if (destination == null || source == null || name.isEmpty) {
      throw FsError(name, FsErrorKind.invalidName);
    }
    return GzipPackParams(source, destination, name);
  }

  const GzipPackParams(this.source, this.destination, this.name);

  final FsNode source;
  final DirectoryNode destination;
  final String name;
}
