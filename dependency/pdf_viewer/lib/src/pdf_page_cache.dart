import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'pdf_document.dart';

/// Отрисованные страницы: что уже есть, что заказано и что пора отпустить.
///
/// Рисуется только видимое — видимые страницы и по одной до и после
/// (`docs/spec/pdf-viewer.md`, §6). Заказ приходит от показа на каждую
/// раскладку; страницы, ушедшие из него, отпускаются сразу: распакованная
/// страница в 16 мегапикселей весит 64 МБ, и держать просмотренные подряд —
/// верный способ съесть память за минуту прокрутки.
class PdfPageCache extends ChangeNotifier {
  PdfPageCache(this.document, {this.parallel = 2});

  final PdfDocument document;

  /// Сколько страниц рисуется одновременно. Больше незачем: у документа в
  /// системе одна очередь, и лишние запросы только стояли бы в ней — а
  /// показ тем временем уехал бы дальше, и они оказались бы ненужными.
  final int parallel;

  /// Наибольшая отрисовка одной страницы — та же, что у раннера (§4).
  static const int maxPixels = 16 * 1000 * 1000;

  /// Шаг ширины отрисовки. Без него каждое движение масштаба заказывало бы
  /// страницу заново на несколько точек шире.
  static const int widthStep = 256;

  final Map<int, ui.Image> _images = {};

  /// Какой ширины заказывали то, что лежит в [_images]. Сравнивается заказ, а
  /// не полученное: система вправе вернуть уже́ (предел точек), и сравнение с
  /// полученным заказывало бы ту же страницу по кругу.
  final Map<int, int> _orderedWidths = {};

  /// Что заказано: страница — нужная ширина.
  Map<int, int> _wanted = const {};

  /// Что рисуется сейчас: страница — ширина.
  final Map<int, int> _rendering = {};

  /// Не нарисовавшиеся: страница — ширина. Без этой отметки отказ тут же
  /// заказывался бы снова, и так по кругу.
  final Map<int, int> _failed = {};

  bool _disposed = false;

  /// Отрисованная страница — та, что есть, хотя бы и не той ширины: мелкая
  /// показывается, пока рисуется крупная, и страница не гаснет при масштабе.
  ui.Image? imageOf(int page) => _images[page];

  /// Ширина отрисовки для страницы, показанной шириной [pixels] точек экрана.
  ///
  /// Вверх до шага, но не больше предела точек: сильнее приблизили — страница
  /// растягивается из наибольшей.
  int widthFor(int page, double pixels) {
    final width = math.max((pixels / widthStep).ceil() * widthStep, widthStep);
    return math.min(width, maxWidthOf(page));
  }

  /// Наибольшая ширина отрисовки страницы — та, при которой она ещё влезает
  /// в предел точек.
  int maxWidthOf(int page) {
    final size = document.pages[page];
    return math.max(math.sqrt(maxPixels * size.width / size.height).floor(), 1);
  }

  /// Какие страницы нужны и какой ширины — по порядку важности: сперва
  /// видимые, потом соседи.
  ///
  /// Синхронно никого не будит: зовут его из раскладки, а будить посреди неё
  /// нельзя.
  void want(Map<int, int> pages) {
    if (_disposed) {
      return;
    }
    _wanted = Map.of(pages);

    // Ушедшее из заказа — отпустить.
    final gone = [
      for (final page in _images.keys)
        if (!pages.containsKey(page)) page,
    ];
    for (final page in gone) {
      _images.remove(page)?.dispose();
      _orderedWidths.remove(page);
    }
    _pump();
  }

  /// Нужна ли странице новая отрисовка.
  ///
  /// Мельче нужной — да. Крупнее вдвое и больше — тоже: отдалили, и держать
  /// страницу в шестнадцать мегапикселей ради показа в два незачем.
  bool _stale(int page, int width) {
    final ordered = _orderedWidths[page];
    if (ordered == null || !_images.containsKey(page)) {
      return true;
    }
    return ordered < width || ordered >= width * 2;
  }

  void _pump() {
    for (final MapEntry(key: page, value: width) in _wanted.entries) {
      if (_rendering.length >= parallel) {
        return;
      }
      if (_rendering.containsKey(page) || _failed[page] == width || !_stale(page, width)) {
        continue;
      }
      _rendering[page] = width;
      unawaited(_render(page, width));
    }
  }

  Future<void> _render(int page, int width) async {
    ui.Image? image;
    try {
      final bytes = await document.handle.render(page, width);
      if (bytes != null && !_disposed && _wanted.containsKey(page)) {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          image = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }
    } on Object {
      // Не нарисовалась — остаётся белый лист. Повторять ту же ширину
      // незачем ([_failed]); другую закажет масштаб.
      image = null;
    } finally {
      _rendering.remove(page);
    }

    if (_disposed || !_wanted.containsKey(page)) {
      image?.dispose();
      return;
    }
    if (image == null) {
      _failed[page] = width;
    } else {
      _failed.remove(page);
      _images.remove(page)?.dispose();
      _images[page] = image;
      _orderedWidths[page] = width;
      notifyListeners();
    }
    _pump();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}
