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

  group('отклик на нажатие мышью', () {
    const metrics = DefaultMetrics();
    const colors = DefaultColors();

    /// Список из трёх строк; курсор на первой.
    Future<List<String>> pump(WidgetTester tester) async {
      final taken = <String>[];
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
                  rows: [
                    FcPickRow(id: 'one', title: 'One'),
                    FcPickRow(id: 'two', title: 'Two'),
                    FcPickRow(id: 'three', title: 'Three'),
                  ],
                  query: '',
                  selected: 0,
                  onTap: taken.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return taken;
    }

    /// Строка с отметкой выбора — по её заливке.
    String? markedRow(WidgetTester tester) {
      for (var i = 0; i < 3; i++) {
        final row = find.ancestor(of: find.text(['One', 'Two', 'Three'][i]), matching: find.byType(Container)).first;
        if (tester.widget<Container>(row).color == colors.cursorBackground) {
          return ['One', 'Two', 'Three'][i];
        }
      }
      return null;
    }

    testWidgets('отметка переезжает на нажатую строку, а дело идёт по отпусканию', (tester) async {
      final taken = await pump(tester);
      expect(markedRow(tester), 'One', reason: 'курсор там, куда его поставили');

      final press = await tester.startGesture(tester.getCenter(find.text('Three')));
      await tester.pump();

      // Кнопка ещё не отпущена: видно, на что попало нажатие, но ничего не
      // случилось — как у кнопок окна.
      expect(markedRow(tester), 'Three');
      expect(taken, isEmpty);

      await press.up();
      await tester.pumpAndSettle();

      expect(taken, ['three']);
    });

    testWidgets('увёл палец со строки — отметка вернулась, выбора нет', (tester) async {
      final taken = await pump(tester);

      final press = await tester.startGesture(tester.getCenter(find.text('Two')));
      await tester.pump();
      expect(markedRow(tester), 'Two');

      await press.moveTo(const Offset(5, 5));
      await press.up();
      await tester.pumpAndSettle();

      expect(taken, isEmpty, reason: 'жест ушёл со строки — он и не выбор');
      expect(markedRow(tester), 'One', reason: 'отметка вернулась туда, где стоит курсор');
    });
  });

  group('номер слева и знак справа', () {
    const metrics = DefaultMetrics();
    const colors = DefaultColors();
    const badgeKey = Key('badge');

    Future<void> pump(WidgetTester tester, FcPickRow row) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [FcTheme(colors: colors, metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts())],
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 600, child: FcPickList(rows: [row], query: '', selected: 0, onTap: (_) {})),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('номер стоит слева от имени и не спорит с ним за место', (tester) async {
      await pump(tester, FcPickRow(id: 'one', title: 'Desktop', leading: '2'));

      final number = tester.getRect(find.text('2'));
      final title = tester.getRect(find.textContaining('Desktop', findRichText: true));

      expect(number.right, lessThanOrEqualTo(title.left + 0.5), reason: 'номер в поле слева, текст под полем ввода');
    });

    testWidgets('знак справа рисуется вместо приписки', (tester) async {
      await pump(tester, const FcPickRow(id: 'one', title: 'Desktop', badge: SizedBox(key: badgeKey, width: 10)));

      expect(find.byKey(badgeKey), findsOneWidget);
    });

    test('место одно: приписка и знак вместе не уживаются', () {
      // Утверждением, а не молчаливым выбором: строка, у которой справа два
      // жильца, — это ошибка вызывающего, и узнать о ней надо сразу.
      expect(
        () => FcPickRow(id: 'one', title: 'Desktop', trailing: 'Alt-1', badge: const SizedBox()),
        throwsA(isA<AssertionError>()),
      );
      expect(
        // Без `const`: у постоянного значения утверждение проверяет компилятор,
        // и до прогона дело не доходит вовсе.
        () => FcPickRow(id: 'one', title: 'Desktop', leading: '2', marked: true),
        throwsA(isA<AssertionError>()),
      );
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
