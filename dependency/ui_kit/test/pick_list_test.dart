import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ход по списку с отбором: стрелки, страницы и правило края.
void main() {
  KeyEvent press(LogicalKeyboardKey key) =>
      KeyDownEvent(logicalKey: key, physicalKey: PhysicalKeyboardKey.keyA, timeStamp: Duration.zero);

  /// Список, у которого в обзоре [size] строк.
  FcPickPage page(int size) => FcPickPage()..size = size;

  group('страницы', () {
    test('страница вниз двигает на видимые строки минус одну', () {
      // Перекрытие в строку не даёт потерять место, где остановился взгляд.
      final moved = FcPickList.moveSelection(
        press(LogicalKeyboardKey.pageDown),
        selected: 0,
        count: 100,
        page: page(10),
      );

      expect(moved, 9);
    });

    test('страница вверх — на столько же назад', () {
      final moved = FcPickList.moveSelection(
        press(LogicalKeyboardKey.pageUp),
        selected: 20,
        count: 100,
        page: page(10),
      );

      expect(moved, 11);
    });

    test('у нижнего края — упор на последнюю строку, а не заворот', () {
      // Стрелка ходит по кругу, но страница с конца в начало от одного нажатия
      // читалась бы не как ход, а как потеря места.
      final moved = FcPickList.moveSelection(
        press(LogicalKeyboardKey.pageDown),
        selected: 8,
        count: 10,
        page: page(10),
      );

      expect(moved, 9);
    });

    test('PgUp с первой страницы даёт первую строку', () {
      final moved = FcPickList.moveSelection(press(LogicalKeyboardKey.pageUp), selected: 3, count: 100, page: page(10));

      expect(moved, 0);
    });

    test('заворота нет и у списка, который ходит по кругу стрелками', () {
      // `wrap` — про стрелки: в палитре они заворачиваются, а страница у края
      // всё равно упирается.
      final moved = FcPickList.moveSelection(press(LogicalKeyboardKey.pageUp), selected: 0, count: 100, page: page(10));

      expect(moved, 0);
    });

    test('на пустом списке обе клавиши молчат', () {
      for (final key in [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.pageDown]) {
        expect(FcPickList.moveSelection(press(key), selected: -1, count: 0, page: page(10)), isNull);
      }
    });

    test('из поля страницей вниз входят в список, вверх — некуда', () {
      // -1 — это «в поле набранное»: вниз оттуда есть куда идти, вверх нет.
      expect(FcPickList.moveSelection(press(LogicalKeyboardKey.pageDown), selected: -1, count: 100, page: page(10)), 8);
      expect(
        FcPickList.moveSelection(press(LogicalKeyboardKey.pageUp), selected: -1, count: 100, page: page(10)),
        isNull,
      );
    });

    test('пока список не раскладывали, страница — одна строка', () {
      // Обзор известен только после раскладки; до неё шаг как у стрелки, а не
      // прыжок в никуда.
      final moved = FcPickList.moveSelection(
        press(LogicalKeyboardKey.pageDown),
        selected: 5,
        count: 100,
        page: FcPickPage(),
      );

      expect(moved, 6);
    });

    test('без записки о странице клавиши остаются вызывающему', () {
      expect(FcPickList.moveSelection(press(LogicalKeyboardKey.pageDown), selected: 0, count: 100), isNull);
    });
  });

  group('стрелки', () {
    test('ходят на строку', () {
      expect(FcPickList.moveSelection(press(LogicalKeyboardKey.arrowDown), selected: 0, count: 10), 1);
      expect(FcPickList.moveSelection(press(LogicalKeyboardKey.arrowUp), selected: 5, count: 10), 4);
    });

    test('с первой вверх уходят в -1, чтобы вернуть набранное', () {
      expect(FcPickList.moveSelection(press(LogicalKeyboardKey.arrowUp), selected: 0, count: 10, wrap: false), -1);
      expect(FcPickList.moveSelection(press(LogicalKeyboardKey.arrowUp), selected: 0, count: 10), 9);
    });
  });
}
