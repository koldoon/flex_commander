import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подсказка договаривает обрезанное (`docs/spec/tooltips.md`).
void main() {
  const colors = DefaultColors();
  const metrics = DefaultMetrics();
  const message = 'очень длинное имя файла, которому не хватило ширины';
  const target = Key('target');

  /// Наведённая мышь: гасится сама, как только тест закончился.
  Future<TestGesture> hover(WidgetTester tester, Finder at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(at));
    await tester.pump();
    return mouse;
  }

  Future<void> pump(WidgetTester tester, {String text = message, Alignment where = Alignment.center}) {
    return pumpScreen(
      tester,
      Align(
        alignment: where,
        child: FcTooltip(message: text, child: const SizedBox(key: target, width: 120, height: 20)),
      ),
    );
  }

  testWidgets('подсказка всплывает не раньше срока', (tester) async {
    await pump(tester);
    await hover(tester, find.byKey(target));

    await tester.pump(FcTooltip.delay - const Duration(milliseconds: 1));
    expect(find.text(message), findsNothing, reason: 'мышь могла просто проезжать мимо');

    await tester.pump(const Duration(milliseconds: 2));
    expect(find.text(message), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('увели мышь до срока — подсказки не было', (tester) async {
    await pump(tester);
    final mouse = await hover(tester, find.byKey(target));

    await tester.pump(const Duration(milliseconds: 300));
    await mouse.moveTo(Offset.zero);
    await tester.pump(FcTooltip.delay);

    expect(find.text(message), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('пустое сообщение — подсказки нет вовсе', (tester) async {
    await pump(tester, text: '');
    await hover(tester, find.byKey(target));
    await tester.pump(FcTooltip.delay * 2);

    expect(
      find.descendant(of: find.byType(FcTooltip), matching: find.byType(MouseRegion)),
      findsNothing,
      reason: 'ни отсчёта, ни наблюдения за мышью: договаривать нечего',
    );

    await disposeScreen(tester);
  });

  group('мышь в панели', () {
    testWidgets('нажатие гасит подсказку и до отпускания не возвращает', (tester) async {
      await pump(tester);
      await hover(tester, find.byKey(target));
      await tester.pump(FcTooltip.delay);
      expect(find.text(message), findsOneWidget);

      final press = await tester.startGesture(tester.getCenter(find.byKey(target)), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.text(message), findsNothing, reason: 'начали жест — подсказка мешает');

      // Протягивание пометки: строки едут под курсором, наведение приходит и с
      // зажатой кнопкой.
      for (var step = 0; step < 5; step++) {
        await press.moveBy(const Offset(0, 4));
        await tester.pump(FcTooltip.delay);
        expect(find.text(message), findsNothing, reason: 'посреди жеста подсказок не бывает');
      }

      await press.up();
      await tester.pump();
      await disposeScreen(tester);
    });

    testWidgets('правая кнопка гасит так же', (tester) async {
      await pump(tester);
      await hover(tester, find.byKey(target));
      await tester.pump(FcTooltip.delay);

      final press = await tester.startGesture(
        tester.getCenter(find.byKey(target)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(find.text(message), findsNothing);

      await press.up();
      await disposeScreen(tester);
    });

    testWidgets('колесо гасит: строка уезжает из-под подсказки', (tester) async {
      await pump(tester);
      await hover(tester, find.byKey(target));
      await tester.pump(FcTooltip.delay);
      expect(find.text(message), findsOneWidget);

      await tester.sendEventToBinding(
        PointerScrollEvent(position: tester.getCenter(find.byKey(target)), scrollDelta: const Offset(0, 40)),
      );
      await tester.pump();

      expect(find.text(message), findsNothing);

      await disposeScreen(tester);
    });

    testWidgets('нажатий подсказка не берёт: щелчок доходит до того, что под ней', (tester) async {
      var tapped = false;
      await pumpScreen(
        tester,
        Center(
          child: FcTooltip(
            message: message,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped = true,
              child: const SizedBox(key: target, width: 120, height: 20),
            ),
          ),
        ),
      );

      await hover(tester, find.byKey(target));
      await tester.pump(FcTooltip.delay);
      expect(find.text(message), findsOneWidget);

      // Щелчок туда, где висит подсказка, а не по виджету через дерево.
      await tester.tapAt(tester.getCenter(find.byKey(target)));
      await tester.pump();

      expect(tapped, isTrue);

      await disposeScreen(tester);
    });
  });

  testWidgets('подсказка не вылезает за край окна', (tester) async {
    await pump(tester, where: Alignment.bottomRight);
    await hover(tester, find.byKey(target));
    await tester.pump(FcTooltip.delay);

    final shown = tester.getRect(find.text(message));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(shown.right, lessThanOrEqualTo(screen.width));
    expect(shown.bottom, lessThanOrEqualTo(screen.height));
    expect(shown.left, greaterThanOrEqualTo(0));
    expect(shown.top, greaterThanOrEqualTo(0), reason: 'снизу тесно — встаёт сверху');

    await disposeScreen(tester);
  });

  testWidgets('виджет ушёл из дерева — подсказка убрана', (tester) async {
    await pump(tester);
    await hover(tester, find.byKey(target));
    await tester.pump(FcTooltip.delay);
    expect(find.text(message), findsOneWidget);

    // Так уезжает строка ленивого списка.
    await pumpScreen(tester, const SizedBox());
    await tester.pump();

    expect(find.text(message), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('оформление взято у окна команды', (tester) async {
    await pump(tester);
    await hover(tester, find.byKey(target));
    await tester.pump(FcTooltip.delay);

    final plate = tester.widget<Container>(
      find.ancestor(of: find.text(message), matching: find.byType(Container)).first,
    );
    final decoration = plate.decoration! as BoxDecoration;

    expect(decoration.color, colors.dialogBackground);
    expect(decoration.borderRadius, BorderRadius.circular(metrics.dialogRadius));
    expect(decoration.border, isNull, reason: 'рамка у сообщения означает отказ — второго значения ей не давать');
    expect(decoration.boxShadow!.single.color, colors.shadow);

    // Стиль проверяется **действующий**, а не тот, что написан у `Text`:
    // накладка — своя ветка отрисовки, и всё, чего стиль не назвал, приходит
    // туда отладочным запасным стилем Flutter (жирное начертание и жёлтое
    // двойное подчёркивание — поймано живьём).
    final shown = DefaultTextStyle.of(tester.element(find.text(message))).style;
    expect(shown.color, colors.dialogText);
    expect(shown.fontFamily, const DefaultFonts().ui);
    expect(shown.decoration ?? TextDecoration.none, TextDecoration.none);
    expect(shown.fontWeight ?? FontWeight.normal, FontWeight.normal);

    await disposeScreen(tester);
  });
}
