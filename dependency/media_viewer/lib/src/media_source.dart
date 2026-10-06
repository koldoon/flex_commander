import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Откуда играть ролик или трек (`docs/spec/video-viewer.md`, §4).
///
/// Система открывает ролик **по пути**: читать гигабайты через канал нельзя.
/// Файл на настоящем диске играет сам, прочий копируется во временный.
class MediaSource {
  MediaSource._(this.path, this._temporary);

  /// Файл на диске — играет сам, убирать за ним нечего.
  MediaSource.local(String path) : this._(path, null);

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
  static Future<MediaSource> prepare(ViewerRequest request, {Directory? under}) => prepareFile(
    request.entry,
    request.content,
    localPath: request.localPath,
    checkpoint: request.checkpoint,
    under: under,
  );

  /// То же для любого файла — следующего трека альбома
  /// (`docs/spec/audio-viewer.md`, §3).
  ///
  /// [content] нужен только для копии: файл с диска ([localPath]) читает сама
  /// система, и содержимое у источника тогда не спрашивают вовсе.
  static Future<MediaSource> prepareFile(
    FileEntry entry,
    Content? content, {
    String? localPath,
    Future<void> Function()? checkpoint,
    Directory? under,
  }) async {
    if (localPath != null) {
      return MediaSource._(localPath, null);
    }
    if (content == null) {
      throw ArgumentError('Не с диска — нужно содержимое для копии: ${entry.path}');
    }

    final directory = await (under ?? Directory.systemTemp).createTemp('fc-media-');
    // Имя — с расширением: по нему система узнаёт формат. Косая черта в имени
    // из архива стала бы лишним каталогом.
    final file = File('${directory.path}/${entry.name.replaceAll('/', '_')}');
    final sink = file.openWrite();
    try {
      await for (final chunk in content.read()) {
        await checkpoint?.call();
        sink.add(chunk);
      }
      await sink.close();
    } catch (_) {
      await _quietly(sink.close);
      await _quietly(() => directory.delete(recursive: true));
      rethrow;
    }
    return MediaSource._(file.path, directory);
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
