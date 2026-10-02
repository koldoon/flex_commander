import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'pdf_viewer_screen.dart';

/// Показ PDF: та же рама и та же плашка, что у панели, текста и картинок.
///
/// Вид один на оба места — во весь экран и в области панели. Разница в раме и
/// в том, кому достаются клавиши; и то и другое спрашивается у области.
class PdfViewerView extends StatefulWidget {
  const PdfViewerView({super.key, required this.screen});

  final PdfViewerScreen screen;

  /// Шаг стрелкой, в точках экрана.
  static const double lineStep = 40;

  /// Подсветка найденного. Не из оформления: страница белая, как бумага, в
  /// любом оформлении, и подсветка лежит на бумаге — как маркер.
  static const Color matchColor = Color(0x66FFD60A);
  static const Color currentMatchColor = Color(0xAAFF9F0A);

  @override
  State<PdfViewerView> createState() => _PdfViewerViewState();
}

class _PdfViewerViewState extends State<PdfViewerView> with SingleTickerProviderStateMixin {
  PdfViewerScreen get screen => widget.screen;

  final FocusNode _focus = FocusNode(debugLabel: 'PdfViewerView');

  late final AnimationController _glide = AnimationController(vsync: this)..addListener(_onGlide);
  Animation<double>? _glideCurve;
  double _glideFrom = 0;

  /// Куда едем; null — стоим. Следующее нажатие считается от него, а не от
  /// того, где окно сейчас: пока клавишу держат, нажатия приходят чаще, чем
  /// доезжает шаг (тот же приём, что у markdown).
  double? _flying;

  bool _focused = false;

  @override
  void dispose() {
    _glide.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Фокус ходит за областью — как у показа текста: вошли — он наш, ушли —
  /// отдаём, пока курсор в файлах, стрелки его.
  void _followFocus(bool focused) {
    if (focused == _focused) {
      return;
    }
    _focused = focused;
    // После кадра: до него узла ещё нет в дереве фокуса, и просьба
    // `autofocus` отклоняется молча (`text_view.dart`).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_focused) {
        _focus.requestFocus();
      } else {
        _focus.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Приложение нужно только в панели: во весь экран рама и фокус известны и
    // так — оба края внешние, ввод его.
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder: (context, _) {
        final focused = app == null || app.view.takesKeys(screen);

        if (screen.showsText) {
          return FcTextView(
            controller: screen.text!,
            finder: screen.textFinder,
            path: screen.entry.path,
            fileName: screen.entry.name,
            trailing: formatBytesLong(screen.entry.size),
            readOnly: true,
            shortcuts: _textShortcuts,
            outerEdge: _edgeOf(app),
            focused: focused,
          );
        }

        _followFocus(focused);
        final strings = context.strings;

        return FcPanelFrame(
          outerEdge: _edgeOf(app),
          // Страницы — сплошное содержимое: им отдана вся рама, плашка ложится
          // поверх, как у картинок.
          fillsFrame: true,
          header: FcPathPlate(
            path: screen.entry.path,
            trailing:
                '${strings.tr('Page {page} of {count}', args: {'page': screen.currentPage + 1, 'count': screen.document.pageCount})}'
                ' · ${formatBytesLong(screen.entry.size)}',
            active: focused,
          ),
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  screen.layoutIn(Size(constraints.maxWidth, constraints.maxHeight));
                  _order(MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);

                  return Listener(
                    onPointerSignal: _onSignal,
                    child: GestureDetector(
                      // От нажатия: иначе страница отстаёт от курсора ровно на то,
                      // что ушло на признание жеста.
                      dragStartBehavior: DragStartBehavior.down,
                      onPanDown: (_) => _stopGlide(),
                      onPanUpdate: (details) => screen.scrollBy(-details.delta),
                      child: _pages(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Заказать отрисовку: видимые страницы, потом по одной до и после.
  void _order(double devicePixelRatio) {
    final visible = screen.visiblePages.toList();
    if (visible.isEmpty) {
      return;
    }
    final rects = screen.pageRects;
    final pages = <int, int>{};
    void add(int page) {
      if (page >= 0 && page < rects.length && !pages.containsKey(page)) {
        pages[page] = screen.cache.widthFor(page, rects[page].width * devicePixelRatio);
      }
    }

    visible.forEach(add);
    add(visible.first - 1);
    add(visible.last + 1);
    screen.cache.want(pages);
  }

  Widget _pages() {
    final offset = screen.offset;
    final rects = screen.pageRects;
    final finder = screen.pageFinder;
    final current = finder.current;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Пустое место тоже ловит мышь: тащат и за поля вокруг страниц.
        const Positioned.fill(child: ColoredBox(color: Color(0x00000000))),
        for (final page in screen.visiblePages)
          Positioned(
            left: rects[page].left - offset.dx,
            top: rects[page].top - offset.dy,
            width: rects[page].width,
            height: rects[page].height,
            child: _Page(
              image: screen.cache.imageOf(page),
              matches: [
                for (final match in finder.matches)
                  if (match.page == page) (match.rects, identical(match, current)),
              ],
            ),
          ),
      ],
    );
  }

  /// Колесо листает, с `Cmd` или `Ctrl` — приближает, как в браузере.
  void _onSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) {
      return;
    }
    _stopGlide();
    if (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) {
      screen.zoomBy(signal.scrollDelta.dy < 0 ? PdfViewerScreen.zoomStep : 1 / PdfViewerScreen.zoomStep);
      return;
    }
    screen.scrollBy(signal.scrollDelta);
  }

  /// Ходьба по документу — внутренние клавиши, как стрелки показа текста
  /// (`docs/spec/pdf-viewer.md`, §7).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final from = _flying ?? screen.offset.dy;
    final page = screen.viewport.height * 0.9;

    final double? target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => from + PdfViewerView.lineStep,
      LogicalKeyboardKey.arrowUp => from - PdfViewerView.lineStep,
      LogicalKeyboardKey.pageDown || LogicalKeyboardKey.space => from + page,
      LogicalKeyboardKey.pageUp => from - page,
      LogicalKeyboardKey.arrowRight => screen.pageStepFrom(from, forward: true),
      LogicalKeyboardKey.arrowLeft => screen.pageStepFrom(from, forward: false),
      _ => null,
    };

    if (event.logicalKey == LogicalKeyboardKey.home || event.logicalKey == LogicalKeyboardKey.end) {
      // К краям — прыжком: доезд через триста страниц только мелькает.
      _stopGlide();
      screen.scrollTo(Offset(screen.offset.dx, event.logicalKey == LogicalKeyboardKey.end ? screen.maxOffset.dy : 0));
      return KeyEventResult.handled;
    }
    if (target == null) {
      return KeyEventResult.ignored;
    }

    final duration = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowUp => const Duration(milliseconds: 90),
      _ => const Duration(milliseconds: 180),
    };
    _glideTo(target.clamp(0, screen.maxOffset.dy), duration);
    return KeyEventResult.handled;
  }

  void _glideTo(double target, Duration duration) {
    _flying = target;
    _glideFrom = screen.offset.dy;
    _glideCurve = CurvedAnimation(parent: _glide, curve: Curves.easeOutCubic);
    _glide
      ..duration = duration
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (_flying == target) {
          _flying = null;
        }
      });
  }

  void _onGlide() {
    final target = _flying;
    final curve = _glideCurve;
    if (target == null || curve == null) {
      return;
    }
    screen.scrollTo(Offset(screen.offset.dx, _glideFrom + (target - _glideFrom) * curve.value));
  }

  /// Мышь и колесо обрывают доезд: иначе он перетягивал бы окно обратно.
  void _stopGlide() {
    if (_glide.isAnimating) {
      _glide.stop();
    }
    _flying = null;
  }

  /// Какие клавиши поле текста отпускает экрану: `Esc` закрывает показ.
  static const FcTextShortcuts _textShortcuts = FcTextShortcuts(
    released: {CodeShortcutType.esc},
    scrollsByArrows: true,
  );

  /// Внешние края рамы: во весь экран оба, в панели — её сторона.
  PanelOuterEdge _edgeOf(Application? app) {
    if (app == null) {
      return PanelOuterEdge.both;
    }
    return switch (app.view.positionOf(screen)) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => PanelOuterEdge.both,
    };
  }
}

/// Одна страница: белый лист, на нём отрисовка и подсветка найденного.
///
/// Пока не отрисована — просто лист нужного размера: раскладка от этого не
/// прыгает, и видно, где страница будет.
class _Page extends StatelessWidget {
  const _Page({required this.image, required this.matches});

  final ui.Image? image;

  /// Найденное на этой странице: прямоугольники в долях и текущее ли оно.
  final List<(List<Rect>, bool)> matches;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            RawImage(
              image: image,
              fit: BoxFit.fill,
              // Растягивается только сверх предела отрисовки (§4) — пусть
              // хоть гладко.
              filterQuality: FilterQuality.medium,
            ),
          if (matches.isNotEmpty) CustomPaint(painter: _MatchPainter(matches)),
        ],
      ),
    );
  }
}

class _MatchPainter extends CustomPainter {
  _MatchPainter(this.matches);

  final List<(List<Rect>, bool)> matches;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (rects, current) in matches) {
      final paint = Paint()..color = current ? PdfViewerView.currentMatchColor : PdfViewerView.matchColor;
      for (final rect in rects) {
        // На волосок шире найденного: впритык подсветка режет края букв.
        final grow = math.max(1.0, rect.height * size.height * 0.1);
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left * size.width,
            rect.top * size.height,
            rect.width * size.width,
            rect.height * size.height,
          ).inflate(grow),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MatchPainter oldDelegate) => true;
}
