import 'dart:async';
import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'pdf_document.dart';
import 'pdf_finder.dart';
import 'pdf_page_cache.dart';
import 'pdf_viewer_settings.dart';

/// Показ PDF: документ, раскладка его страниц и то, как их сейчас смотрят.
///
/// Прокрутка своя, а не `Scrollable`: размеры всех страниц известны с
/// открытия, раскладка точная, и прокрутке остаётся одно смещение по двум
/// осям — его и держим (`docs/spec/pdf-viewer.md`, §3).
class PdfViewerScreen extends ChangeNotifier implements ViewerContent, FcSearchable {
  PdfViewerScreen({
    required FileEntry entry,
    required this.document,
    required this.settings,
    required this.onSettingsChanged,
    this.place = ViewerPlace.fullscreen,
  }) : _entry = entry {
    cache = PdfPageCache(document)..addListener(notifyListeners);
    pageFinder = PdfFinder(document, reveal: revealMatch)..addListener(notifyListeners);
  }

  /// Имя в реестре просмотрщиков — и для команд поиска.
  static const String viewerId = 'pdf';

  /// Поля вокруг документа и промежуток между страницами, в точках экрана.
  static const double margin = 12;
  static const double gap = 12;

  /// Наименьший и наибольший масштаб — от «по ширине». Шаг — корень из двух,
  /// те же числа, что у картинок.
  static const double minZoom = 0.1;
  static const double maxZoom = 8;
  static const double zoomStep = 1.4142135623730951;

  final PdfDocument document;
  final PdfViewerSettings settings;
  final void Function() onSettingsChanged;

  late final PdfPageCache cache;
  late final PdfFinder pageFinder;

  @override
  final ViewerPlace place;

  @override
  FileEntry get entry => _entry;
  final FileEntry _entry;

  // --- Раскладка --------------------------------------------------------------

  /// Размер окна показа; пусто — ещё не раскладывали.
  Size get viewport => _viewport;
  Size _viewport = Size.zero;

  /// Где окно в документе: верхний левый угол, в точках экрана.
  Offset get offset => _offset;
  Offset _offset = Offset.zero;

  /// Свой масштаб — во сколько раз крупнее «по ширине»; null — вид по
  /// настройке.
  double? _zoom;

  /// Вписан ли документ видом из настройки — или масштаб задан руками.
  bool get fits => _zoom == null;

  /// Страница целиком сейчас — или по ширине.
  bool get wholePage => _zoom == null && settings.wholePage;

  /// Масштаб «по ширине»: самая широкая страница — во всю ширину окна.
  double get _fitWidth {
    final widest = document.pages.map((page) => page.width).reduce(math.max);
    return math.max((_viewport.width - 2 * margin) / widest, 0.01);
  }

  /// Точек экрана на пункт страницы.
  double get scale {
    if (_viewport.isEmpty) {
      return 1;
    }
    final fitWidth = _fitWidth;
    if (_zoom case final zoom?) {
      return fitWidth * zoom;
    }
    if (settings.wholePage) {
      final tallest = document.pages.map((page) => page.height).reduce(math.max);
      return math.min(fitWidth, math.max((_viewport.height - 2 * margin) / tallest, 0.01));
    }
    return fitWidth;
  }

  /// Страницы в документе, в точках экрана.
  List<Rect> get pageRects => _layout().$1;

  /// Размер всего документа, в точках экрана.
  Size get contentSize => _layout().$2;

  (List<Rect>, Size)? _laidOut;
  (double, double)? _laidOutFor;

  (List<Rect>, Size) _layout() {
    final s = scale;
    final key = (s, _viewport.width);
    if (_laidOut case final laidOut? when _laidOutFor == key) {
      return laidOut;
    }
    final widest = document.pages.map((page) => page.width).reduce(math.max) * s;
    final width = math.max(_viewport.width, widest + 2 * margin);
    final rects = <Rect>[];
    var top = margin;
    for (final page in document.pages) {
      final w = page.width * s;
      final h = page.height * s;
      rects.add(Rect.fromLTWH((width - w) / 2, top, w, h));
      top += h + gap;
    }
    final size = Size(width, top - gap + margin);
    _laidOutFor = key;
    return _laidOut = (rects, size);
  }

  /// Наибольшее смещение по обеим осям.
  Offset get maxOffset {
    final size = contentSize;
    return Offset(math.max(size.width - _viewport.width, 0), math.max(size.height - _viewport.height, 0));
  }

  /// Окно показа поменяло размер. Зовёт раскладка — поэтому молча.
  ///
  /// Место чтения остаётся: та же страница и та же её доля сверху.
  void layoutIn(Size viewport) {
    if (viewport == _viewport || viewport.isEmpty) {
      return;
    }
    final anchor = _viewport.isEmpty ? null : _anchor();
    _viewport = viewport;
    _restore(anchor);
  }

  /// Страница, занимающая середину окна, — её номер в плашке.
  int get currentPage => _pageAt(_offset.dy + _viewport.height / 2);

  /// Страница под точкой [y] документа; между страницами — ближайшая ниже.
  int _pageAt(double y) {
    final rects = pageRects;
    for (var i = 0; i < rects.length; i++) {
      if (y < rects[i].bottom + gap) {
        return i;
      }
    }
    return rects.length - 1;
  }

  /// Видимые страницы — по номерам.
  Iterable<int> get visiblePages sync* {
    final top = _offset.dy;
    final bottom = top + _viewport.height;
    final rects = pageRects;
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].bottom >= top && rects[i].top <= bottom) {
        yield i;
      }
    }
  }

  /// Место чтения: страница сверху окна, доля её высоты над краем и середина
  /// окна по горизонтали в долях ширины документа.
  (int, double, double) _anchor() {
    final top = _offset.dy;
    final page = _pageAt(top);
    final rect = pageRects[page];
    final along = rect.height == 0 ? 0.0 : (top - rect.top) / rect.height;
    final across = contentSize.width == 0 ? 0.5 : (_offset.dx + _viewport.width / 2) / contentSize.width;
    return (page, along, across);
  }

  void _restore((int, double, double)? anchor) {
    if (anchor == null) {
      _offset = _clamp(_offset);
      return;
    }
    final (page, along, across) = anchor;
    final rect = pageRects[page];
    _offset = _clamp(Offset(across * contentSize.width - _viewport.width / 2, rect.top + along * rect.height));
  }

  Offset _clamp(Offset value) {
    final limit = maxOffset;
    return Offset(value.dx.clamp(0, limit.dx), value.dy.clamp(0, limit.dy));
  }

  // --- Ход и масштаб ----------------------------------------------------------

  /// Сдвинуть окно по документу.
  void scrollBy(Offset delta) => scrollTo(_offset + delta);

  void scrollTo(Offset target) {
    final next = _clamp(target);
    if (next == _offset) {
      return;
    }
    _offset = next;
    notifyListeners();
  }

  /// Где верх окна стоит, когда страница [page] показана с начала.
  double topOf(int page) => math.max(pageRects[page].top - margin, 0);

  /// Начало следующей или предыдущей страницы — считая от [from].
  ///
  /// Назад — к началу **текущей**, если её начало уже ушло за край: так
  /// листают и книгу.
  double pageStepFrom(double from, {required bool forward}) {
    final rects = pageRects;
    if (forward) {
      for (var i = 0; i < rects.length; i++) {
        if (topOf(i) > from + 1) {
          return topOf(i);
        }
      }
      return maxOffset.dy;
    }
    for (var i = rects.length - 1; i >= 0; i--) {
      if (topOf(i) < from - 1) {
        return topOf(i);
      }
    }
    return 0;
  }

  /// Вернуться к виду из настройки, а из него — переключить «по ширине /
  /// страница целиком».
  void toggleFit() {
    final anchor = _viewport.isEmpty ? null : _anchor();
    if (_zoom != null) {
      _zoom = null;
    } else {
      settings.wholePage = !settings.wholePage;
      onSettingsChanged();
    }
    _restore(anchor);
    notifyListeners();
  }

  /// Приблизить или отдалить; место чтения остаётся на месте.
  void zoomBy(double factor) {
    if (_viewport.isEmpty) {
      return;
    }
    final anchor = _anchor();
    final current = scale / _fitWidth;
    _zoom = (current * factor).clamp(minZoom, maxZoom);
    _restore(anchor);
    notifyListeners();
  }

  /// Показать найденное: если оно не видно целиком — в середину окна.
  void revealMatch(PdfMatch match) {
    if (_viewport.isEmpty) {
      return;
    }
    final page = pageRects[match.page];
    final found = match.bounds;
    final rect = Rect.fromLTWH(
      page.left + found.left * page.width,
      page.top + found.top * page.height,
      found.width * page.width,
      found.height * page.height,
    );
    final window = _offset & _viewport;
    if (window.contains(rect.topLeft) && window.contains(rect.bottomRight)) {
      return;
    }
    scrollTo(
      Offset(
        window.left <= rect.left && rect.right <= window.right ? _offset.dx : rect.center.dx - _viewport.width / 2,
        rect.center.dy - _viewport.height / 2,
      ),
    );
  }

  // --- Текст документа (`F5`) ------------------------------------------------

  /// Показан текст вместо страниц.
  bool get showsText => _showsText && _text != null;
  bool _showsText = false;

  /// Текст документа; null — ещё не доставали.
  CodeLineEditingController? get text => _text;
  CodeLineEditingController? _text;

  FcTextFinder? _textFinder;

  /// Поиск по тексту — когда показан текст.
  FcTextFinder? get textFinder => _text == null ? null : _textFinder ??= FcTextFinder(_text!);

  /// Достать текст: по первому `F5`, а не при открытии — это дорого (§8).
  ///
  /// Возвращает, есть ли он вовсе: у скана текста нет.
  Future<bool> loadText() async {
    if (_text != null) {
      return true;
    }
    final loaded = _loadingText ??= document.handle.text();
    final content = await loaded;
    if (_disposed || content.trim().isEmpty) {
      return false;
    }
    _text ??= CodeLineEditingController.fromText(content);
    return true;
  }

  Future<String>? _loadingText;

  /// Переключить «страницы / текст». Текст должен быть уже на руках.
  void toggleText() {
    if (_text == null) {
      return;
    }
    _showsText = !_showsText;
    notifyListeners();
  }

  // --- Поиск -----------------------------------------------------------------

  @override
  String get id => viewerId;

  /// Ищет тот, кто виден: текст — в тексте, страницы — система.
  @override
  FcFinder get finder => showsText ? textFinder! : pageFinder;

  // --- Жизнь -----------------------------------------------------------------

  @override
  bool get takesKeyboard => true;

  @override
  void close() => dispose();

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    cache.dispose();
    pageFinder.dispose();
    _textFinder?.dispose();
    _text?.dispose();
    // Закрыли показ — отпустили документ в раннере: быстрый просмотр, идущий
    // по каталогу, иначе копил бы их там все.
    unawaited(document.close());
    super.dispose();
  }
}
