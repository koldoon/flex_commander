import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

import 'image_viewer_settings.dart';

/// Прочитанная картинка: байты и то, что о них известно **до** распаковки.
///
/// Размеры и формат берутся из заголовка, а не из распакованного растра: в
/// этом весь смысл — по ним и решается, распаковывать ли вообще.
class ImageDocument {
  ImageDocument({required this.bytes, required this.width, required this.height, required this.format});

  final Uint8List bytes;

  /// Чем показывать: один источник на весь показ.
  ///
  /// Держится здесь, а не собирается видом на каждую перерисовку: у показа и у
  /// предварительной распаковки должен быть **один и тот же** ключ в кеше
  /// картинок, иначе распаковали одно, а рисуем другое.
  late final MemoryImage image = MemoryImage(bytes);
  final int width;
  final int height;

  /// `PNG`, `JPEG`, `GIF`, `WEBP`, `BMP` — по сигнатуре, а не по имени файла:
  /// имя врёт чаще, чем первые байты.
  final String format;

  /// Сколько точек. По нему проверяется предел памяти.
  int get pixels => width * height;

  /// Читает файл и разбирает его заголовок.
  ///
  /// Отказ — [ViewerRefused] с причиной словами; каждая называет и выход:
  /// системный просмотр открывает то, чего не умеем мы.
  static Future<ImageDocument> read(
    FsNode node,
    ImageViewerSettings settings, {
    required Future<void> Function() checkpoint,
  }) async {
    final source = node.provider;
    if (source is! FileContentProvider) {
      throw const ViewerRefused('No content here to show');
    }
    if (node.size > settings.maxFileSize) {
      throw ViewerRefused(
        'Image is too large: ${formatBytesLong(node.size)}, '
        'limit is ${formatSize(settings.maxFileSize)} — open it with the system (Cmd-O)',
      );
    }

    final chunks = <int>[];
    await for (final chunk in await (source as FileContentProvider).openRead(node)) {
      // Курсор в быстром просмотре мог уйти дальше: дочитывать незачем.
      await checkpoint();
      chunks.addAll(chunk);
    }
    await checkpoint();

    final bytes = Uint8List.fromList(chunks);
    final size = await _sizeOf(bytes);
    if (size == null) {
      // Заголовок не разобрался — значит, это не картинка или формат не наш.
      // Сказать об этом надо здесь, а не после того, как распаковка съест
      // память.
      throw const ViewerRefused('Not an image, or the format is not supported (Cmd-O opens it with the system)');
    }

    final pixels = size.$1 * size.$2;
    if (pixels > settings.maxPixels) {
      throw ViewerRefused(
        'Image is ${size.$1}×${size.$2}, limit is ${settings.maxPixels ~/ 1000000} MP '
        '— open it with the system (Cmd-O)',
      );
    }

    return ImageDocument(bytes: bytes, width: size.$1, height: size.$2, format: _formatOf(bytes));
  }

  /// Распаковать заранее — до того, как картинку покажут.
  ///
  /// Иначе видно чужое: пока новая картинка распаковывается, показ рисует
  /// прежнюю (`gaplessPlayback`), а коробка уже нового размера — и прежняя
  /// растягивается в чужие пропорции на те полсекунды, что идёт распаковка.
  /// Живая проверка это и поймала.
  ///
  /// Ошибку распаковки здесь не ловим и не прячем: до сюда доходит только то,
  /// чей заголовок уже разобран, а если распаковка всё же не удалась — пусть
  /// об этом скажет показ, а не тишина.
  Future<void> warmUp() {
    if (_stream != null) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    void done(_, _) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    final stream = image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(done, onError: (_, _) => done(null, null));
    _stream = stream;
    _listener = listener;
    // Слушателя **не снимаем**: пока на распакованную картинку кто-то смотрит,
    // кеш держит её живой и вытеснить не может. Отпустим — и при беглом
    // листании она вылетит из кеша ровно тогда, когда её собрались показать.
    stream.addListener(listener);
    return completer.future;
  }

  /// Отпустить распакованное: картинку сменили или показ закрыли.
  ///
  /// Без этого кеш держал бы живыми все просмотренные подряд — а их за минуту
  /// листания набирается столько, сколько в память не влезет.
  void release() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// Размеры из заголовка; null — заголовок не разобрался.
  ///
  /// Разбирает его сам движок показа (`ImageDescriptor`), а не наш код: он
  /// знает ровно те форматы, которые потом и покажет, и расходиться им негде.
  static Future<(int, int)?> _sizeOf(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (descriptor.width, descriptor.height);
    } on Object {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Формат по сигнатуре — тому, с чего файл начинается.
  static String _formatOf(Uint8List bytes) {
    bool starts(List<int> signature, {int at = 0}) {
      if (bytes.length < at + signature.length) {
        return false;
      }
      for (var i = 0; i < signature.length; i++) {
        if (bytes[at + i] != signature[i]) {
          return false;
        }
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4e, 0x47])) {
      return 'PNG';
    }
    if (starts([0xff, 0xd8, 0xff])) {
      return 'JPEG';
    }
    if (starts([0x47, 0x49, 0x46, 0x38])) {
      return 'GIF';
    }
    // `RIFF….WEBP`: четыре байта подписи, четыре длины, и только потом формат.
    if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], at: 8)) {
      return 'WEBP';
    }
    if (starts([0x42, 0x4d])) {
      return 'BMP';
    }
    // Показать сможем — назвать нет: заголовок разобрался, а подпись чужая.
    return 'Image';
  }
}
