import 'dart:ui';

/// Чем меряют и чем рисуют текст диаграммы.
///
/// Одним и тем же объектом: замерил — этим же и нарисовал. Иначе меряем одно, а
/// рисуем другое, и подпись вылезает из коробки (`docs/spec/mermaid.md`, §5).
abstract interface class DiagramTextRun {
  /// Сколько места занял замеренный текст.
  Size get size;

  /// Нарисовать в точке — левый верхний угол.
  void paint(Canvas canvas, Offset at);
}

/// Роль текста: ею выбирают начертание и цвет.
enum DiagramTextRole {
  /// Подпись участника в шапке столбца.
  participant,

  /// Подпись сообщения над стрелкой.
  message,

  /// Текст заметки.
  note,

  /// Ярлык рамки: `alt`, `else`, `loop`.
  blockLabel,

  /// Порядковый номер сообщения.
  number,
}

/// Замер текста. В тестах подставной — тогда координаты становятся точными
/// числами, а утверждения — осмысленными.
abstract interface class DiagramTextMeasure {
  DiagramTextRun run(String text, DiagramTextRole role, {double maxWidth});
}
