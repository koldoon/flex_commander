import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сравнение снимков с допуском на округление растеризации.
///
/// Эталоны снимаются на раннере CI (macOS 26), а у разработчика стоит
/// macOS 27: тот же Flutter растеризует сглаженный край на единицу-другую
/// иначе. Точное сравнение на этом краснело локально — четырнадцать снимков,
/// по 4–92 точки на снимок, и каждая отличалась на 1–2 единицы цвета
/// (`docs/spec/design-system.md`, отметка от 1 октября 2026). Красный, который
/// не значит ничего, перестают читать — и следующая настоящая поломка пройдёт
/// незамеченной.
///
/// Допуск — **на точку**, а не на долю снимка: точка совпала, если ни один её
/// канал не ушёл дальше [tolerance]. Сдвиг раскладки, другой цвет, лишний или
/// пропавший элемент дают расхождения в десятки и сотни единиц и ловятся
/// по-прежнему; доля в процентах этого не различала бы — сдвиг строки на
/// точку весит столько же, сколько сглаживание всего окна.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = RasterTolerantComparator(current.basedir.resolve('flutter_test_config.dart'));
  }
  await testMain();
}

class RasterTolerantComparator extends LocalFileComparator {
  RasterTolerantComparator(super.testFile);

  /// Насколько может разойтись один канал одной точки.
  ///
  /// Восемь — с запасом над самым большим из встреченных округлений (7, у
  /// значков сетки) и далеко ниже любого настоящего различия.
  static const int tolerance = 8;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = Uint8List.fromList(await getGoldenBytes(golden));
    final result = await GoldenFileComparator.compareLists(imageBytes, goldenBytes);
    if (result.passed) {
      result.dispose();
      return true;
    }
    if (await _withinTolerance(imageBytes, goldenBytes)) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }

  static Future<bool> _withinTolerance(Uint8List test, Uint8List master) async {
    final a = await _rgba(test);
    final b = await _rgba(master);
    if (a == null || b == null || a.width != b.width || a.height != b.height) {
      return false;
    }
    final left = a.bytes;
    final right = b.bytes;
    for (var i = 0; i < left.length; i++) {
      if ((left[i] - right[i]).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  static Future<({int width, int height, Uint8List bytes})?> _rgba(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = data == null ? null : (width: image.width, height: image.height, bytes: data.buffer.asUint8List());
    image.dispose();
    codec.dispose();
    return result;
  }
}
