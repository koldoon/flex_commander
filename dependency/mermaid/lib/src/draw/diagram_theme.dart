import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'diagram_layout.dart';
import 'diagram_text.dart';

/// Чем рисовать диаграмму: цвета и начертания из темы приложения.
///
/// Только существующие роли: новая потянула бы за собой оформление по
/// умолчанию, редактор тем и макет (`docs/spec/mermaid.md`, §9).
class DiagramStyle {
  const DiagramStyle({
    required this.text,
    required this.line,
    required this.fill,
    required this.edge,
    required this.bar,
    required this.faint,
    required this.plate,
    required this.onPlate,
    required this.background,
    required this.stroke,
  });

  factory DiagramStyle.of(BuildContext context) {
    final theme = FcTheme.of(context);
    final base = FcTheme.effective(context, theme.uiStyle);
    final faintText = base.copyWith(color: theme.colors.secondaryText);

    return DiagramStyle(
      text: {
        // Надпись на плашке — цветом фона панели: плашка инвертирована.
        DiagramTextRole.participant: base.copyWith(color: theme.colors.panelBackground, fontWeight: FontWeight.w600),
        DiagramTextRole.message: base.copyWith(color: theme.colors.rowText),
        DiagramTextRole.note: base.copyWith(color: theme.colors.rowText),
        DiagramTextRole.blockLabel: faintText,
        DiagramTextRole.number: faintText,
      },
      // Цветом текста, а не рамки: `panelBorder` — «белый 15%», и стрелки на
      // нём выходили бледнее собственных подписей. Стрелка — главное на
      // диаграмме, её и видно первой.
      line: theme.colors.rowText,
      fill: theme.colors.dialogListBackground,
      edge: theme.colors.dialogListBorder,
      bar: theme.colors.markedBar,
      faint: theme.colors.secondaryText,
      // Тем же цветом, что и линии жизни: плашка и линия — одно целое.
      plate: theme.colors.secondaryText,
      onPlate: theme.colors.panelBackground,
      background: theme.colors.panelBackground,
      stroke: theme.metrics.strokeWidth,
    );
  }

  final Map<DiagramTextRole, TextStyle> text;

  /// Линии и стрелки.
  final Color line;

  /// Заливка коробок.
  final Color fill;

  /// Граница коробок.
  final Color edge;

  /// Полоса активности.
  final Color bar;

  /// Второстепенное: рамки блоков, ярлыки.
  final Color faint;

  /// Плашка участника — залита цветом линий жизни.
  final Color plate;

  /// Надпись на плашке — цветом фона панели.
  final Color onPlate;

  /// Фон, которым подкладывают надписи, чтобы они не тонули в линиях.
  final Color background;

  final double stroke;

  /// Толщина линии вызова.
  ///
  /// В 1.2 раза против обычной: стрелка на диаграмме главная, и волосяной
  /// линии ей мало.
  double get arrowStroke => stroke * 1.2;

  Color colorOf(DiagramInk ink) => switch (ink) {
    DiagramInk.line => line,
    DiagramInk.fill => fill,
    DiagramInk.plate => plate,
    DiagramInk.bar => bar,
    DiagramInk.faint => faint,
  };
}

/// Настоящий замер: тем же `TextPainter`, которым текст потом и рисуется.
class DiagramPainterMeasure implements DiagramTextMeasure {
  const DiagramPainterMeasure(this.style, this.direction);

  final DiagramStyle style;
  final TextDirection direction;

  @override
  DiagramTextRun run(String text, DiagramTextRole role, {double maxWidth = double.infinity}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style.text[role]),
      textDirection: direction,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    return _PainterRun(painter);
  }
}

class _PainterRun implements DiagramTextRun {
  const _PainterRun(this._painter);

  final TextPainter _painter;

  @override
  Size get size => _painter.size;

  @override
  void paint(Canvas canvas, Offset at) => _painter.paint(canvas, at);
}
