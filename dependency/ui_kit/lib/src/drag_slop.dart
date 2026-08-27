import 'package:flutter/gestures.dart';

/// Сколько нужно провести указателем, чтобы это считалось перетаскиванием.
///
/// У мыши Flutter считает перетаскиванием сдвиг на **одну точку**
/// (`kPrecisePointerHitSlop`), и настройками это не меняется: `computeHitSlop`
/// для мыши возвращает её мимо `DeviceGestureSettings`. А живая рука сдвигает
/// указатель на точку-другую в любом щелчке — и распознаватель перетаскивания
/// забирает нажатие себе прежде, чем успевает сработать щелчок.
///
/// Так однажды перестала работать сортировка по заголовку колонки: клик по ней
/// не срабатывал вовсе, а тесты этого не видели, потому что «нажимали»
/// идеально ровно.
///
/// Отсюда правило, одно на всё приложение: **щелчок — это меньше восьми точек,
/// а не ровно ноль.**
const double kFcDragSlop = 8;

/// Перетаскивание вбок, начинающееся с [kFcDragSlop].
class FcHorizontalDragRecognizer extends HorizontalDragGestureRecognizer {
  FcHorizontalDragRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > kFcDragSlop;
}
