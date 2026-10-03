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
    this.openWith,
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

  /// Чем отдать внешнюю ссылку системе; null — нечем, и щелчок по ней молчит
  /// только потому, что открыть её и правда некому.
  final SystemOpener? openWith;

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

  // --- Переходы: оглавление и ссылки (§16) --------------------------------

  /// Где на документе точка [target], в точках экрана.
  double _yOf(PdfTarget target) {
    final rect = pageRects[target.page];
    return target.top == null ? topOf(target.page) : rect.top + target.top! * rect.height;
  }

  /// Место чтения сейчас: страница сверху окна и доля её высоты. Долей, а не
  /// точками: между переходами масштаб мог поменяться.
  PdfTarget get readingPlace {
    final top = _offset.dy;
    final page = _pageAt(top);
    final rect = pageRects[page];
    return PdfTarget(page, top: rect.height == 0 ? 0 : ((top - rect.top) / rect.height).clamp(0.0, 1.0));
  }

  final List<PdfTarget> _back = [];
  final List<PdfTarget> _forward = [];

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// Перейти — по оглавлению или по ссылке. Откуда ушли, запоминается.
  ///
  /// Прокрутка историю не пишет: это чтение, а не переход (§16.3).
  void jumpTo(PdfTarget target) {
    if (target.page < 0 || target.page >= document.pageCount) {
      return;
    }
    _back.add(readingPlace);
    _forward.clear();
    _show(target);
  }

  void goBack() => _walk(_back, _forward);

  void goForward() => _walk(_forward, _back);

  void _walk(List<PdfTarget> from, List<PdfTarget> to) {
    if (from.isEmpty) {
      return;
    }
    to.add(readingPlace);
    // Запомненное место — ровно туда, где стояли: поле под краем нужно
    // заголовку, к которому переходят, а не месту, откуда ушли.
    _show(from.removeLast(), exact: true);
  }

  void _show(PdfTarget target, {bool exact = false}) {
    // Место назначения — у верхнего края, с тем же полем, что над первой
    // страницей: заголовок раздела не должен прилипать к краю окна.
    final y = exact || target.top == null ? _yOf(target) : _yOf(target) - margin;
    scrollTo(Offset(_offset.dx, y));
    // Стоим там же — всё равно сказать показу: номер страницы и кнопки
    // «назад» в ряду должны обновиться.
    notifyListeners();
  }

  /// Оглавление; достаётся по первому `F6` и один раз.
  Future<List<PdfOutlineItem>> loadOutline() => _outline ??= document.handle.outline();
  Future<List<PdfOutlineItem>>? _outline;

  /// Текущий раздел — последний заголовок, начало которого не ниже верха окна.
  int currentSectionOf(List<PdfOutlineItem> outline) {
    final top = _offset.dy + 1;
    var current = 0;
    for (var i = 0; i < outline.length; i++) {
      final target = outline[i].target;
      if (target.page >= document.pageCount) {
        continue;
      }
      final y = target.top == null ? pageRects[target.page].top : _yOf(target) - margin;
      if (y <= top + margin) {
        current = i;
      }
    }
    return current;
  }

  /// Ссылки страницы — когда уже достали; пока нет — пусто, и они
  /// достаются: щелчок не должен ждать раннера (§16.2).
  List<PdfLink> linksOf(int page) {
    if (_links[page] case final links?) {
      return links;
    }
    if (_asked.add(page)) {
      unawaited(
        document.handle.links(page).then((links) {
          if (_disposed) {
            return;
          }
          _links[page] = links;
          if (links.isNotEmpty) {
            notifyListeners();
          }
        }),
      );
    }
    return const [];
  }

  final Map<int, List<PdfLink>> _links = {};
  final Set<int> _asked = {};

  /// Ссылка под точкой [point] окна показа; null — нет её там.
  PdfLink? linkAt(Offset point) {
    final at = point + _offset;
    final rects = pageRects;
    for (final page in visiblePages) {
      final rect = rects[page];
      if (!rect.contains(at)) {
        continue;
      }
      final local = Offset((at.dx - rect.left) / rect.width, (at.dy - rect.top) / rect.height);
      for (final link in linksOf(page)) {
        if (link.rect.contains(local)) {
          return link;
        }
      }
    }
    return null;
  }

  // --- Выделение на страницах (§17) ----------------------------------------

  /// Страница под точкой окна и где на ней — в долях. [nearest] — точка мимо
  /// страниц всё равно даёт ближайшую, прижатую к её краю: так протяжка,
  /// ушедшая в поле или за край окна, продолжает выделять.
  PdfPoint? pointAt(Offset point, {bool nearest = false}) {
    if (_viewport.isEmpty) {
      return null;
    }
    final at = point + _offset;
    final rects = pageRects;
    var best = -1;
    var distance = double.infinity;
    for (var i = 0; i < rects.length; i++) {
      final rect = rects[i];
      if (rect.contains(at)) {
        best = i;
        break;
      }
      if (!nearest) {
        continue;
      }
      final dy = at.dy < rect.top ? rect.top - at.dy : (at.dy > rect.bottom ? at.dy - rect.bottom : 0.0);
      if (dy < distance) {
        distance = dy;
        best = i;
      }
    }
    if (best < 0) {
      return null;
    }
    final rect = rects[best];
    return PdfPoint(
      best,
      Offset(((at.dx - rect.left) / rect.width).clamp(0.0, 1.0), ((at.dy - rect.top) / rect.height).clamp(0.0, 1.0)),
    );
  }

  /// Выделенное; null — ничего.
  PdfSelection? get selection => _selection;
  PdfSelection? _selection;

  bool get hasSelection => _selection?.text.isNotEmpty ?? false;

  /// Откуда тянут.
  PdfPoint? _selectionStart;

  /// Начать выделение в точке окна: протяжкой — пока только запомнить, словом
  /// и строкой — сразу спросить раннер.
  void startSelection(Offset point, {PdfSelectionUnit unit = PdfSelectionUnit.character}) {
    final start = pointAt(point);
    if (start == null) {
      clearSelection();
      return;
    }
    _selectionStart = start;
    if (unit == PdfSelectionUnit.character) {
      _dropSelection();
      return;
    }
    _ask((start, null, unit));
  }

  /// Тянут дальше — выделение до точки под мышью.
  void extendSelection(Offset point) {
    final start = _selectionStart;
    final end = pointAt(point, nearest: true);
    if (start == null || end == null) {
      return;
    }
    _ask((start, end, PdfSelectionUnit.character));
  }

  void clearSelection() {
    _selectionStart = null;
    _dropSelection();
  }

  void _dropSelection() {
    // Ответ, который ещё в пути, уже не про это выделение.
    _selectionGeneration++;
    _wanted = null;
    if (_selection != null) {
      _selection = null;
      notifyListeners();
    }
  }

  /// Что спросить следующим. Вопросы идут **по одному**: пока раннер считает,
  /// новые положения мыши только заменяют друг друга, и спрашивается последнее
  /// — показ отстаёт на кадр, а не копит очередь (§17.4).
  (PdfPoint, PdfPoint?, PdfSelectionUnit)? _wanted;
  bool _asking = false;
  int _selectionGeneration = 0;

  /// Сколько вопросов ушло в раннер — для проверки, что они не копятся.
  @visibleForTesting
  int selectionRequests = 0;

  void _ask((PdfPoint, PdfPoint?, PdfSelectionUnit) wanted) {
    _wanted = wanted;
    if (!_asking) {
      unawaited(_askNext());
    }
  }

  Future<void> _askNext() async {
    _asking = true;
    try {
      while (_wanted != null && !_disposed) {
        final (from, to, unit) = _wanted!;
        _wanted = null;
        final generation = _selectionGeneration;
        selectionRequests++;
        final answer = await document.handle.select(from, to: to, unit: unit);
        if (_disposed || generation != _selectionGeneration) {
          continue;
        }
        _selection = answer;
        notifyListeners();
      }
    } finally {
      _asking = false;
    }
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
