import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_updater/fc_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно «новая версия готова»: заметки выпуска разметкой и два ответа
/// (`docs/spec/self-update.md`, §9).
void main() {
  const metrics = DefaultMetrics();

  /// Заметки такие же, какими их пишут в `docs/release-notes.md`.
  const notes = '''
Сервер, который не принимает подключения, теперь **так и говорит**.

* `Cannot connect` — не дозвонились.
* `I/O error` — связь есть, не вышло другое.

| каталог | было | стало |
|---|---|---|
| `/tmp` | 278 мс | 36 мс |''';

  Future<void> pump(WidgetTester tester, {String data = notes, VoidCallback? later, VoidCallback? restart}) async {
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
              width: 600,
              height: 400,
              child: UpdateReadyView(notes: data, onLater: later ?? () {}, onRestart: restart ?? () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('заметки показаны разметкой, а не сырым текстом', (tester) async {
    await pump(tester);

    expect(find.byType(MarkdownBody), findsOneWidget);
    // Звёздочки выделения в показанном тексте не встречаются: их отрисовали,
    // а не напечатали.
    final shown = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? '').join();
    expect(shown, isNot(contains('**')));
  });

  testWidgets('длинные заметки прокручиваются', (tester) async {
    // Окно бывает меньше рассказа о выпуске — и это обычное дело.
    await pump(tester, data: List.generate(80, (i) => 'Строка $i').join('\n\n'));

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('пустым заметкам — своя строка, а не пустота', (tester) async {
    await pump(tester, data: '   ');

    expect(find.text('No release notes'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
  });

  testWidgets('оба ответа на месте и отзываются', (tester) async {
    var later = 0;
    var restart = 0;
    await pump(tester, later: () => later++, restart: () => restart++);

    await tester.tap(find.widgetWithText(FcButton, 'Later'));
    await tester.tap(find.widgetWithText(FcButton, 'Restart'));
    await tester.pump();

    expect(later, 1);
    expect(restart, 1);
  });
}
