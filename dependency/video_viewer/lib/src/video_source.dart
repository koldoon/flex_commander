import 'dart:async';
import 'dart:io';

import 'package:fc_ui_api/fc_ui_api.dart';

/// Откуда играть ролик (`docs/spec/video-viewer.md`, §4).
///
/// Система открывает ролик **по пути**: читать гигабайты через канал нельзя.
/// Файл на настоящем диске играет сам, прочий копируется во временный.
class VideoSource {
  VideoSource._(this.path, this._temporary);

  /// Файл на диске — играет сам, убирать за ним нечего.
  VideoSource.local(String path) : this._(path, null);

  /// Путь, который отдают системе.
  final String path;

  /// Временный каталог копии; null — играет сам файл, убирать нечего.
  final Directory? _temporary;

  /// Ролик играет из копии, а не с места.
  bool get copied => _temporary != null;

  /// Путь к ролику — свой или копии.
  ///
  /// Копия читается кусками с точкой прерывания: курсор в быстром просмотре
  /// уходит дальше, и докачивать ролик, который уже не нужен, незачем. Отмена
  /// и сбой копию убирают.
  static Future<VideoSource> prepare(ViewerRequest request, {Directory? under}) async {
    final local = request.localPath;
    if (local != null) {
      return VideoSource._(local, null);
    }

    final directory = await (under ?? Directory.systemTemp).createTemp('fc-video-');
    // Имя — с расширением: по нему система узнаёт формат. Косая черта в имени
    // из архива стала бы лишним каталогом.
    final file = File('${directory.path}/${request.entry.name.replaceAll('/', '_')}');
    final sink = file.openWrite();
    try {
      await for (final chunk in request.content.read()) {
        await request.checkpoint();
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await _quietly(sink.close);
      await _quietly(() => directory.delete(recursive: true));
      rethrow;
    }
    return VideoSource._(file.path, directory);
  }

  /// Убрать копию; у файла с диска убирать нечего.
  Future<void> dispose() async {
    final temporary = _temporary;
    if (temporary != null) {
      await _quietly(() => temporary.delete(recursive: true));
    }
  }

  /// Уборка не роняет закрытие: не удалилось — останется во временном
  /// каталоге системы, который она чистит сама.
  static Future<void> _quietly(Future<Object?> Function() work) async {
    try {
      await work();
    } on Object {
      // Не удалилось — не беда, см. выше.
    }
  }
}
