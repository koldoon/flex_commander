import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
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

  group('путь двумя цветами', () {
    const metrics = DefaultMetrics();
    const colors = DefaultColors();

    Future<void> pump(WidgetTester tester, String title, {bool dimPathHead = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [FcTheme(colors: colors, metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts())],
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: FcPickList(
                  rows: [FcPickRow(id: '0', title: title)],
                  query: '',
                  // Курсора нет: у строки под ним свой цвет, и проверять надо
                  // обычную.
                  selected: -1,
                  dimPathHead: dimPathHead,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Кусочки строки со своими цветами — так видно, чем набрана каждая часть.
    List<(String, Color?)> partsOf(WidgetTester tester) {
      final parts = <(String, Color?)>[];
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text != null) {
            parts.add((span.text!, span.style?.color));
          }
          for (final child in span.children ?? const <InlineSpan>[]) {
            walk(child);
          }
        }
      }

      walk(tester.widget<Text>(find.byType(Text).first).textSpan!);
      return parts;
    }

    testWidgets('ярко только последнее звено', (tester) async {
      await pump(tester, '/home/koldoon/Developer');

      final parts = partsOf(tester);
      expect(parts.map((part) => part.$1).join(), '/home/koldoon/Developer');
      expect(parts.first.$2, colors.dialogText, reason: 'начало пути должно быть приглушено');
      expect(parts.last.$2, colors.dialogLabel, reason: 'последнее звено — ярко');
    });

    testWidgets('строке без разделителя делить нечего', (tester) async {
      await pump(tester, 'Copy File');

      expect(partsOf(tester).map((part) => part.$2).toSet(), {colors.dialogLabel});
    });

    testWidgets('хвостовой разделитель делению не мешает', (tester) async {
      // Такие строки остались в настройках от прежних времён: показать их надо
      // так же, как нынешние, — ярким последним звеном.
      await pump(tester, '/Users/koldoon/Developer/');

      final parts = partsOf(tester);
      expect(parts.map((part) => part.$1).join(), '/Users/koldoon/Developer');
      expect(parts.last.$2, colors.dialogLabel, reason: 'последнее звено — ярко');
      expect(parts.first.$2, colors.dialogText);
    });

    testWidgets('у корня нет звена, которое стоило бы выделить', (tester) async {
      await pump(tester, '/');

      expect(partsOf(tester).map((part) => part.$2).toSet(), {colors.dialogLabel});
    });

    testWidgets('обычный список приглушения не знает', (tester) async {
      await pump(tester, '/home/koldoon/Developer', dimPathHead: false);

      expect(partsOf(tester).map((part) => part.$2).toSet(), {colors.dialogLabel});
    });
  });
}
