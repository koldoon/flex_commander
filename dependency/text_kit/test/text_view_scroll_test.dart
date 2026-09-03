import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Листание показа текста: смотрим на положение прокрутки, а не на строку
/// курсора.
///
/// Курсор здесь — подробность реализации: в просмотрщике его не видно, и
/// человек судит о нажатии по тому, поехал ли текст. Поэтому каждая проверка —
/// про `ScrollPosition.pixels`, и лишь там, где нужно доказать «ровно на одну
/// строку», рядом стоит строка курсора.
void main() {
  // Пятьсот строк: заведомо больше экрана, и до конца листать и листать.
  final String text = List.generate(500, (index) => 'строка $index').join('\n');

  /// Клавиши доходят до поля только на настольной платформе: на Android и iOS
  /// `CodeEditor` строит ветку **без** `Shortcuts` вовсе, и тест «прошёл бы», не
  /// проверив ничего. Признак снимается здесь же, в теле: из `tearDown` уже
  /// поздно — проверка инвариантов срабатывает раньше.
  ///
  /// Виджет снимается тоже здесь: пока поле в фокусе, курсор моргает по
  /// таймеру, и с живым таймером тест не закончится. Редактор вдобавок
  /// откладывает на десять миллисекунд разговор с системным вводом — этот
  /// таймер при сносе не отменяется, поэтому сначала кадр подольше.
  Future<void> onDesktop(WidgetTester tester, Future<void> Function() body) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    }
  }

  Future<CodeLineEditingController> pump(
    WidgetTester tester, {
    required bool readOnly,
    required bool scrollsByArrows,
  }) async {
    final CodeLineEditingController controller = CodeLineEditingController.fromText(text);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: FcTextView(
            controller: controller,
            path: '/home/big.txt',
            fileName: 'big.txt',
            readOnly: readOnly,
            shortcuts: FcTextShortcuts(scrollsByArrows: scrollsByArrows),
          ),
        ),
      ),
    );
    // Фокус поле просит следующим кадром после появления: без него клавиши до
    // него не дойдут.
    await tester.pump();
    await tester.pump();
    return controller;
  }

  /// Вертикальная прокрутка поля. Их две — вторая крутит текст вбок.
  ScrollPosition scroll(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .map((ScrollableState state) => state.position)
      .firstWhere((ScrollPosition position) => position.axis == Axis.vertical);

  /// Прокрутка случается сразу, курсор подтягивается следующим кадром — два
  /// кадра — это оба шага.
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump();
  }

  Future<void> wheel(WidgetTester tester, double delta) async {
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(CodeEditor)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, delta)));
    await tester.pump();
  }

  group('страница', () {
    testWidgets('первый PgDn листает на экран без одной строки', (tester) async {
      await onDesktop(tester, () async {
        await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        // Шаг строки меряем стрелкой — она крутит ровно на строку, — и
        // возвращаемся к началу. Так «страница» проверяется тем, чем она
        // задана: экраном без одной строки перекрытия.
        await press(tester, LogicalKeyboardKey.arrowDown);
        final double line = position.pixels;
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(position.pixels, 0);
        expect(line, greaterThan(0));

        await press(tester, LogicalKeyboardKey.pageDown);

        expect(position.pixels, position.viewportDimension - line);
      });
    });

    testWidgets('курсор после листания виден целиком, а не торчит за верхний край', (tester) async {
      // Поймано на живом: открыть файл и сразу нажать `PgDn`. Курсор стоит на
      // первой строке, то есть в самом верхнем ряду экрана, — и держится за
      // этот ряд. Но страница почти никогда не кратна строке, и ряд, покрывший
      // верхнюю точку нового экрана, **начинается выше** неё: видны только его
      // нижние пиксели, а сам курсор рисуется над краем.
      await onDesktop(tester, () async {
        final CodeLineEditingController controller = await pump(tester, readOnly: false, scrollsByArrows: false);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.pageDown);
        final double page = position.pixels;
        final double line = position.viewportDimension - page;

        // Верх строки, на которую сел курсор, — не выше верха экрана.
        expect(controller.selection.extentIndex * line, greaterThanOrEqualTo(position.pixels));
      });
    });

    testWidgets('каждое следующее нажатие листает на столько же', (tester) async {
      // Отставание на страницу выглядело именно так: первое нажатие не двигало
      // экран, а дальше шаг был правильный.
      await onDesktop(tester, () async {
        await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.pageDown);
        final double page = position.pixels;
        await press(tester, LogicalKeyboardKey.pageDown);

        expect(position.pixels, page * 2);
      });
    });

    testWidgets('PgUp сразу после PgDn возвращает туда, откуда листнули', (tester) async {
      // Разворот съедал нажатие: курсор переезжал на видимую строку, и экран
      // оставался на месте.
      await onDesktop(tester, () async {
        await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.pageDown);
        await press(tester, LogicalKeyboardKey.pageDown);
        final double there = position.pixels;
        await press(tester, LogicalKeyboardKey.pageUp);

        expect(position.pixels, there / 2);
      });
    });

    testWidgets('PgDn после колеса листает от накрученного места', (tester) async {
      // Колесо крутит окно и не трогает курсор. Раньше PgDn отбрасывал экран
      // назад, к курсору.
      await onDesktop(tester, () async {
        await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.pageDown);
        final double page = position.pixels;
        await press(tester, LogicalKeyboardKey.pageUp);

        await wheel(tester, 400);
        expect(position.pixels, 400);

        await press(tester, LogicalKeyboardKey.pageDown);

        expect(position.pixels, 400 + page);
      });
    });

    testWidgets('у конца файла прокрутка упирается, а курсор доходит до последней строки', (tester) async {
      await onDesktop(tester, () async {
        final CodeLineEditingController controller = await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        // Тридцать нажатий на пятистах строках — заведомо мимо конца.
        for (int i = 0; i < 30; i++) {
          await press(tester, LogicalKeyboardKey.pageDown);
        }

        expect(position.pixels, position.maxScrollExtent);
        expect(controller.selection.extentIndex, 499);

        // И от края PgUp листает с первого нажатия.
        await press(tester, LogicalKeyboardKey.pageUp);

        expect(position.pixels, lessThan(position.maxScrollExtent));
      });
    });
  });

  group('стрелки', () {
    testWidgets('в просмотрщике первый Down крутит текст на строку', (tester) async {
      await onDesktop(tester, () async {
        final CodeLineEditingController controller = await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.arrowDown);

        expect(position.pixels, greaterThan(0));
        // Курсор едет вместе с окном: он стоял на верхней строке экрана, там же
        // и остался — а верхней стала следующая строка файла.
        expect(controller.selection.extentIndex, 1);
      });
    });

    testWidgets('от начала файла Up не делает ничего: крутить некуда', (tester) async {
      await onDesktop(tester, () async {
        final CodeLineEditingController controller = await pump(tester, readOnly: true, scrollsByArrows: true);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.arrowUp);

        expect(position.pixels, 0);
        expect(controller.selection.extentIndex, 0);
      });
    });

    testWidgets('в редакторе Down двигает курсор и не крутит текст', (tester) async {
      // Проверка на то, что мы не унесли поведение редактора вместе с
      // просмотрщиком: там каретку видно, и шаг на строку — её шаг.
      await onDesktop(tester, () async {
        final CodeLineEditingController controller = await pump(tester, readOnly: false, scrollsByArrows: false);
        final ScrollPosition position = scroll(tester);

        await press(tester, LogicalKeyboardKey.arrowDown);

        expect(controller.selection.extentIndex, 1);
        expect(position.pixels, 0);

        // А когда курсор дойдёт до нижней строки, экран за ним поедет.
        for (int i = 0; i < 40; i++) {
          await press(tester, LogicalKeyboardKey.arrowDown);
        }

        expect(controller.selection.extentIndex, 41);
        expect(position.pixels, greaterThan(0));
      });
    });
  });
}
