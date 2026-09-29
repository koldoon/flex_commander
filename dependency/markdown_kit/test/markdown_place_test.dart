import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Место чтения: показ открывается на заданном блоке и говорит, какой блок
/// сейчас сверху (`docs/spec/markdown-viewer.md`, §8).
///
/// Ради этого всё и затевалось: `F5` не должен отбрасывать человека в начало
/// документа.
void main() {
  // Сорок разделов: заведомо длиннее экрана, и каждый узнаётся по подписи.
  final source = [for (var i = 0; i < 40; i++) '## Раздел $i\n\nТекст раздела $i.\n'].join('\n');

  Future<void> pump(WidgetTester tester, {int? startAtBlock, void Function(int)? onTopBlock}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: FcMarkdownView(
                document: FcMarkdownDocument.parse(source),
                startAtBlock: startAtBlock,
                onTopBlock: onTopBlock,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('без просьбы документ открывается с начала', (tester) async {
    await pump(tester);

    expect(find.text('Раздел 0'), findsOneWidget);
    expect(find.text('Раздел 20'), findsNothing);
  });

  testWidgets('просили блок — с него и открылся', (tester) async {
    // Блок 40 — это «## Раздел 20»: на каждый раздел приходится заголовок и
    // абзац.
    await pump(tester, startAtBlock: 40);

    expect(find.text('Раздел 20'), findsOneWidget);
    expect(find.text('Раздел 0'), findsNothing, reason: 'начало документа осталось выше');
  });

  testWidgets('открытый блок стоит сверху, а не где придётся', (tester) async {
    await pump(tester, startAtBlock: 40);

    final view = tester.getRect(find.byType(FcMarkdownView));
    final block = tester.getRect(find.text('Раздел 20'));

    expect(block.top - view.top, lessThan(view.height / 3), reason: 'иначе место чтения всё равно уехало');
  });

  testWidgets('докрутили — сказано, какой блок сверху', (tester) async {
    final seen = <int>[];
    await pump(tester, onTopBlock: seen.add);

    expect(seen, isEmpty, reason: 'пока не крутили — и говорить не о чем');

    // Прокруткой, а не перетаскиванием: клавиши и колесо ходят через неё же,
    // а перетаскивание внутри `SelectionArea` — это ещё и выделение.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(600);
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty);
    expect(seen.last, greaterThan(0));
  });

  testWidgets('названный блок — тот, что видно сверху', (tester) async {
    final seen = <int>[];
    await pump(tester, onTopBlock: seen.add);

    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(900);
    await tester.pumpAndSettle();

    // Заголовок раздела N — блок 2N: проверяем, что названный блок и правда
    // стоит у верхней кромки, а не просто «какой-то из построенных».
    final view = tester.getRect(find.byType(FcMarkdownView));
    final top = seen.last;
    final label = top.isEven ? 'Раздел ${top ~/ 2}' : 'Текст раздела ${top ~/ 2}.';
    final block = tester.getRect(find.text(label));

    expect(block.bottom, greaterThan(view.top), reason: 'названный блок уже уехал вверх');
    expect(block.top, lessThan(view.top + view.height / 3));
  });
}
