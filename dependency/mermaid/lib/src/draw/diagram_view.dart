import 'package:flutter/widgets.dart';

import 'diagram_layout.dart';
import 'diagram_painter.dart';
import 'diagram_theme.dart';

/// Показ готовой диаграммы: вписать, а не влезло — дать прокрутить.
///
/// Раскладку считает тот, кто дал [build]: этот виджет её только показывает и
/// помнит, чтобы не пересчитывать на каждую перерисовку
/// (`docs/spec/mermaid.md`, §8).
class MermaidDiagramView extends StatefulWidget {
  const MermaidDiagramView({super.key, required this.build, required this.maxWidth});

  /// Посчитать раскладку замером, который даст показ.
  final DiagramLayout Function(DiagramPainterMeasure measure) build;

  /// Сколько места дали по ширине.
  final double maxWidth;

  /// Меньше этого не ужимаем: ниже порога текст превращается в серую рябь, и
  /// прокрутить честнее, чем показать нечитаемое.
  static const double minScale = 0.55;

  @override
  State<MermaidDiagramView> createState() => _MermaidDiagramViewState();
}

class _MermaidDiagramViewState extends State<MermaidDiagramView> {
  DiagramLayout? _layout;
  DiagramStyle? _style;
  double _width = double.nan;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Сменилась тема — стиль другой, и замер другой: считаем заново.
    _layout = null;
    _style = null;
  }

  @override
  void didUpdateWidget(MermaidDiagramView old) {
    super.didUpdateWidget(old);
    if (old.build != widget.build || old.maxWidth != widget.maxWidth) {
      _layout = null;
    }
  }

  DiagramLayout _layoutOf(BuildContext context) {
    final style = _style ??= DiagramStyle.of(context);

    if (_layout case final ready? when _width == widget.maxWidth) {
      return ready;
    }
    _width = widget.maxWidth;

    return _layout = widget.build(DiagramPainterMeasure(style, Directionality.of(context)));
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layoutOf(context);
    final style = _style!;

    if (layout.size.isEmpty) {
      return const SizedBox.shrink();
    }

    final fits = !widget.maxWidth.isFinite || layout.size.width <= widget.maxWidth;
    final wanted = fits ? 1.0 : widget.maxWidth / layout.size.width;
    final scale = wanted < MermaidDiagramView.minScale ? MermaidDiagramView.minScale : wanted;

    final picture = SizedBox(
      width: layout.size.width * scale,
      height: layout.size.height * scale,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: CustomPaint(painter: DiagramPainter(layout: layout, style: style)),
        ),
      ),
    );

    if (!fits && wanted < MermaidDiagramView.minScale) {
      // Ужать дальше нельзя — пусть едет вбок. Полоса прокрутки сама скажет,
      // что диаграмма шире места.
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: picture);
    }

    return picture;
  }
}
