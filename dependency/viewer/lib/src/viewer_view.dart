import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:flutter/material.dart';

import 'viewer_screen.dart';

/// Показ файла: заголовок сверху, текст под ним.
///
/// Рисуются только те строки, что попали на экран, — этим занимается
/// `ListView.builder`, и он же держит небольшой запас сверху и снизу. Файл в
/// тысячи строк поэтому открывается мгновенно: разбирается он целиком, а
/// рисуется по горсти строк за раз.
class ViewerView extends StatefulWidget {
  const ViewerView({super.key, required this.screen});

  final ViewerScreen screen;

  @override
  State<ViewerView> createState() => _ViewerViewState();
}

class _ViewerViewState extends State<ViewerView> {
  /// Строки, уже разобранные подсветкой. Разбор идёт один раз на файл: он не
  /// зависит ни от прокрутки, ни от переноса строк.
  List<TextSpan>? _spans;
  TextStyle? _style;

  /// Ширина знака моноширинного шрифта — по ней считается ширина холста.
  double _charWidth = 0;

  /// Поля вокруг текста. Полосы прокрутки в них не входят: они стоят по краю
  /// панели, а поля отодвигают от них сам текст.
  EdgeInsets _textPadding = EdgeInsets.zero;

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.screen.attachScroller(_scroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final theme = FcTheme.of(context);
    final style = TextStyle(
      fontFamily: theme.fonts.fixed,
      fontSize: theme.metrics.fontSize,
      color: theme.colors.rowText,
      height: 1.35,
    );

    _textPadding = EdgeInsets.symmetric(
      horizontal: theme.metrics.panelLeftPadding,
      vertical: theme.metrics.cellPadding,
    );

    if (_style == style) {
      return;
    }
    _style = style;
    _charWidth = _measureCharWidth(style);
    _spans = widget.screen
        .highlighterFor(theme.colors)
        .highlight(widget.screen.document.lines, fileName: widget.screen.node.name, base: style);
  }

  @override
  void dispose() {
    widget.screen.detachScroller(_scroll);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Двигает показ по просьбе команды.
  ///
  /// Контроллеры живут здесь, а не в экране: их надо закрывать, а экран о
  /// кадрах ничего не знает. Прыжком, а не плавно: клавишу держат нажатой, и
  /// анимация каждого шага догоняла бы палец.
  void _scroll(ScrollStep step) {
    final vertical = _vertical.hasClients ? _vertical.position : null;
    final horizontal = _horizontal.hasClients ? _horizontal.position : null;

    switch (step) {
      case ScrollStep.lineUp:
        _moveBy(vertical, -_lineHeight);
      case ScrollStep.lineDown:
        _moveBy(vertical, _lineHeight);
      case ScrollStep.pageUp:
        _moveBy(vertical, -(vertical?.viewportDimension ?? 0));
      case ScrollStep.pageDown:
        _moveBy(vertical, vertical?.viewportDimension ?? 0);
      case ScrollStep.toStart:
        vertical?.jumpTo(vertical.minScrollExtent);
        horizontal?.jumpTo(horizontal.minScrollExtent);
      case ScrollStep.toEnd:
        vertical?.jumpTo(vertical.maxScrollExtent);
      case ScrollStep.columnLeft:
        _moveBy(horizontal, -_charWidth * _columnStep);
      case ScrollStep.columnRight:
        _moveBy(horizontal, _charWidth * _columnStep);
    }
  }

  /// Сколько знаков проматывает одно нажатие вбок.
  static const int _columnStep = 8;

  static void _moveBy(ScrollPosition? position, double delta) {
    if (position == null || delta == 0) {
      return;
    }
    position.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  /// Ширина знака: шрифт моноширинный, поэтому меряется один раз, а не на
  /// каждую строку. Иначе длину холста пришлось бы считать раскладкой всего
  /// текста — того самого, которого мы и не хотим раскладывать целиком.
  static double _measureCharWidth(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '0' * 100, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width / 100;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: widget.screen,
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: theme.metrics.panelGap / 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(screen: widget.screen),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colors.panelBackground,
                    border: Border.all(color: theme.colors.panelBorder, width: theme.metrics.strokeWidth),
                  ),
                  // Отступ здесь — только для полос прокрутки: они стоят по
                  // краю панели, а текст отодвигают уже свои поля.
                  child: Padding(
                    padding: EdgeInsets.all(theme.metrics.scrollbarInset),
                    child: widget.screen.wordWrap ? _wrapped() : _plain(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Без переноса: холст бывает шире окна, и тогда его возят по обеим осям.
  ///
  /// Уже окна холст не бывает: у длинного, но узкого файла он растягивается до
  /// края. Иначе вертикальная полоса прокрутки вставала бы по правому краю
  /// **текста** — посреди пустого места, — а не по краю окна, где её ищут.
  Widget _plain() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = widget.screen.document.longestLine * _charWidth + _charWidth + _textPadding.horizontal;

        return Scrollbar(
          controller: _vertical,
          // Видна всегда, а не только пока крутят: полоса заодно показывает,
          // насколько файл длиннее окна, — а исчезающая говорит об этом лишь
          // тому, кто уже крутит.
          thumbVisibility: true,
          // Вертикальная полоса — **снаружи** горизонтальной прокрутки, потому
          // и по краю окна. Список из-за этого лежит на уровень глубже, и
          // уведомления от него приходят с глубиной 1.
          notificationPredicate: (notification) => notification.depth == 1,
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: math.max(text, constraints.maxWidth), child: _lines(softWrap: false)),
            ),
          ),
        );
      },
    );
  }

  /// С переносом: возить по ширине нечего, длинная строка занимает несколько
  /// экранных.
  Widget _wrapped() => Scrollbar(controller: _vertical, thumbVisibility: true, child: _lines(softWrap: true));

  Widget _lines({required bool softWrap}) {
    final spans = _spans ?? const <TextSpan>[];

    return ListView.builder(
      controller: _vertical,
      // Поля вокруг текста — у списка, а не снаружи полос: иначе полосы
      // отъехали бы от рамки вместе с текстом.
      padding: _textPadding,
      // Не главный список экрана: прокруткой с клавиатуры занимаются команды
      // просмотрщика, а не фокус и не `PrimaryScrollController`.
      primary: false,
      itemCount: spans.length,
      // Строки одной высоты — список знает, где какая, и не раскладывает всё
      // подряд ради прокрутки. С переносом высота у строк разная, и подсказку
      // дать нечем.
      itemExtent: softWrap ? null : _lineHeight,
      itemBuilder: (context, index) => Text.rich(spans[index], softWrap: softWrap, maxLines: softWrap ? null : 1),
    );
  }

  double get _lineHeight {
    final style = _style;
    return style == null ? 0 : (style.fontSize ?? 0) * (style.height ?? 1);
  }
}

/// Заголовок: что открыто и какого оно размера.
class _Header extends StatelessWidget {
  const _Header({required this.screen});

  final ViewerScreen screen;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Container(
      height: metrics.pathHeaderHeight,
      margin: EdgeInsets.only(bottom: metrics.rowGap),
      padding: EdgeInsets.symmetric(horizontal: metrics.labelPadding),
      decoration: BoxDecoration(
        color: theme.colors.pathBackground,
        border: Border.all(color: theme.colors.pathBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.pathHeaderRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              // Полный адрес, а не одно имя: файл может лежать в архиве или на
              // сервере, и по имени этого не видно.
              screen.node.displayPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.pathStyle,
            ),
          ),
          SizedBox(width: metrics.columnGap),
          Text(formatBytesLong(screen.node.size), style: theme.pathStyle.copyWith(color: theme.colors.secondaryText)),
        ],
      ),
    );
  }
}
