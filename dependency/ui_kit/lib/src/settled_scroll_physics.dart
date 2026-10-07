import 'package:flutter/widgets.dart';

/// Прокрутка, которая за край уходит только под рукой.
///
/// Список, ставший короче без жеста, — вошли в маленький каталог, перечитали,
/// дочитали по частям, — прокрутку не пружинит, а сразу ставит в пределы.
/// Пружина у края — ответ на жест, и без жеста она выглядит непрошенной
/// анимацией. Под пальцем на трекпаде всё как было: физика платформы остаётся
/// родителем.
///
/// Стандартный `RangeMaintainingScrollPhysics` этого не делает: прыжок,
/// сделанный между двумя раскладками, он считает намеренным и в пределы не
/// возвращает. А прыжок к курсору по меркам прежнего списка как раз такой.
class SettledScrollPhysics extends ScrollPhysics {
  const SettledScrollPhysics({super.parent});

  @override
  SettledScrollPhysics applyTo(ScrollPhysics? ancestor) => SettledScrollPhysics(parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final pixels = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    if (isScrolling || velocity != 0) {
      return pixels;
    }
    return pixels.clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
  }
}
