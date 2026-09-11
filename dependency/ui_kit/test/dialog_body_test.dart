import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тело окна: содержимое и ряд кнопок под ним
/// (`docs/spec/dialog-body.md`).
void main() {
  const metrics = DefaultMetrics();

  /// Тело окна в отведённом ему месте.
  ///
  /// [height] — высота, назначенная окну; null — окно облегает содержимое, и
  /// высоты ему никто не задавал.
  Future<void> pump(
    WidgetTester tester, {
    double? height,
    double contentHeight = 100,
    List<Widget> actions = const [],
    FcDialogInsets insets = FcDialogInsets.all,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: height,
              // Ровно то, что делает рама окна: объявляет, задан ли размер.
              child: FcDialogSizing(
                stretches: height != null,
                child: FcDialogBody(
                  actions: actions,
                  insets: insets,
                  child: Container(
                    key: const ValueKey('content'),
                    height: contentHeight,
                    color: const Color(0xFF102030),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect content(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('content')));

  Rect body(WidgetTester tester) => tester.getRect(find.byType(FcDialogBody));

  testWidgets('окну без заданной высоты тело облегает содержимое', (tester) async {
    await pump(tester, actions: [FcButton(label: 'Close', onPressed: () {})]);

    final buttons = tester.getRect(find.byType(FcDialogActions));
    // Содержимое со своими полями плюс ряд кнопок — и ничего сверх того.
    expect(
      body(tester).height,
      moreOrLessEquals(100 + metrics.dialogContentTopPadding + metrics.dialogPadding + buttons.height, epsilon: 0.5),
    );
  });

  testWidgets('заданную высоту тело отдаёт содержимому, а кнопки держит внизу', (tester) async {
    await pump(tester, height: 400, actions: [FcButton(label: 'Close', onPressed: () {})]);

    final buttons = tester.getRect(find.byType(FcDialogActions));
    expect(buttons.bottom, moreOrLessEquals(body(tester).bottom, epsilon: 0.5), reason: 'ряд кнопок не внизу');
    // Содержимому досталось всё, что осталось от ряда кнопок и полей.
    expect(
      content(tester).height,
      moreOrLessEquals(400 - buttons.height - metrics.dialogContentTopPadding - metrics.dialogPadding, epsilon: 0.5),
    );
  });

  testWidgets('содержимое выше отведённого прокручивается, а не вылезает', (tester) async {
    await pump(tester, contentHeight: 2000, actions: [FcButton(label: 'Close', onPressed: () {})]);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('растянутому окну своей прокрутки тело не ставит', (tester) async {
    // Иначе она съела бы заданную высоту, а листать себя внутри растянутого
    // окна умеет само содержимое — своим списком и своим контроллером.
    await pump(tester, height: 400, contentHeight: 2000);

    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('поля по краям ставит тело, а без них содержимое доходит до краёв', (tester) async {
    await pump(tester);
    expect(content(tester).left - body(tester).left, moreOrLessEquals(metrics.dialogHorizontalPadding, epsilon: 0.5));

    await pump(tester, insets: FcDialogInsets.vertical);
    expect(content(tester).left, moreOrLessEquals(body(tester).left, epsilon: 0.5));
    // Вертикальные остаются в обоих случаях: содержимое отходит от полосы
    // заголовка сверху и от края окна снизу.
    expect(content(tester).top - body(tester).top, moreOrLessEquals(metrics.dialogContentTopPadding, epsilon: 0.5));
  });

  testWidgets('окно без кнопок ряда не имеет вовсе', (tester) async {
    await pump(tester);

    expect(find.byType(FcDialogActions), findsNothing);
    // И места он не занимает: снизу только собственное поле содержимого.
    expect(body(tester).bottom - content(tester).bottom, moreOrLessEquals(metrics.dialogPadding, epsilon: 0.5));
  });
}
