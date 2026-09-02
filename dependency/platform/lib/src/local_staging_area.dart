import 'dart:async';
import 'dart:io';

import 'package:fc_core_api/fc_core_api.dart';
import 'package:path/path.dart' as p;

/// Временные файлы в локальной файловой системе.
///
/// Реализация [StagingArea] для настоящего диска: `dart:io` живёт здесь, а не
/// в API, поэтому провайдер архива или сетевого источника обходится контрактом
/// и не тянет за собой платформу.
class LocalStagingArea implements StagingArea {
  const LocalStagingArea({this.root});

  /// Где заводить временные каталоги; null — там, где их заводит система.
  ///
  /// Задаётся в тестах: временные файлы разных работ иначе перемешиваются в
  /// общем каталоге системы, и проверить «за собой убрано» становится нечем.
  final Directory? root;

  @override
  Future<StagedDirectory> open(String prefix) async {
    return _LocalStagedDirectory(await (root ?? Directory.systemTemp).createTemp('${prefix}_'));
  }
}

class _LocalStagedDirectory implements StagedDirectory {
  _LocalStagedDirectory(this._directory);

  final Directory _directory;
  bool _disposed = false;

  @override
  String get path => _directory.path;

  @override
  Future<String> write(String name, Stream<List<int>> content) async {
    final target = File(p.join(_directory.path, name));
    final sink = target.openWrite();

    try {
      await sink.addStream(content);
      await sink.close();
    } on Object {
      // Недокачанный файл выглядит как целый — его нельзя оставлять даже
      // до уборки каталога.
      await sink.close().catchError((Object _) {});
      await target.delete().catchError((Object _) => target);
      rethrow;
    }

    return target.path;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    try {
      if (await _directory.exists()) {
        await _directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Убрать не вышло: временный каталог переживёт нас, но молчать об
      // этом лучше, чем сбивать с толку посреди чужой ошибки.
    }
  }
}
