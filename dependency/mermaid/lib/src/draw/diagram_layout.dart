import 'dart:ui';

import 'diagram_text.dart';

/// Чем красить фигуру.
enum DiagramInk {
  /// Линии и рамки.
  line,

  /// Заливка коробок.
  fill,

  /// Плашка участника: она инвертирована — залита цветом линий, а надпись на
  /// ней цветом фона.
  plate,

  /// Полоса активности.
  bar,

  /// Второстепенное: ярлыки рамок, номера.
  faint,
}

/// Чем кончается линия.
enum DiagramHead {
  none,

  /// Сплошной треугольник.
  arrow,

  /// Крестик.
  cross,

  /// Открытая «галочка».
  open,
}

/// Готовая диаграмма: размер и фигуры в порядке отрисовки.
///
/// Отрисовка ничего не считает — ей приносят это (`docs/spec/mermaid.md`, §5).
class DiagramLayout {
  const DiagramLayout({required this.size, required this.shapes});

  final Size size;
  final List<DiagramShape> shapes;

  /// Пустая — рисовать нечего.
  static const DiagramLayout empty = DiagramLayout(size: Size.zero, shapes: []);
}

sealed class DiagramShape {
  const DiagramShape();
}

/// Прямоугольник: шапка участника, коробка заметки, рамка блока, полоса
/// активности.
class DiagramBox extends DiagramShape {
  const DiagramBox({
    required this.rect,
    this.radius = 0,
    this.ink = DiagramInk.line,
    this.filled = true,
    this.dashed = false,
  });

  final Rect rect;
  final double radius;
  final DiagramInk ink;

  /// Заливать ли: рамка блока — нет, коробка участника — да.
  final bool filled;

  final bool dashed;
}

/// Ломаная: стрелка сообщения, линия жизни, черта между ветвями.
class DiagramPath extends DiagramShape {
  const DiagramPath({
    required this.points,
    this.head = DiagramHead.none,
    this.dashed = false,
    this.ink = DiagramInk.line,
  });

  /// Точки по порядку; двух хватает на прямую.
  final List<Offset> points;

  final DiagramHead head;
  final bool dashed;
  final DiagramInk ink;
}

/// Замеренный текст на своём месте.
class DiagramLabel extends DiagramShape {
  const DiagramLabel({required this.run, required this.at, this.backdrop = false});

  final DiagramTextRun run;

  /// Левый верхний угол.
  final Offset at;

  /// Подложить под надпись фон.
  ///
  /// Надпись сидит поверх линий жизни и рамок, и без подложки буквы тонут в
  /// них. Плашке участника подложка не нужна: она сама себе фон.
  final bool backdrop;
}
