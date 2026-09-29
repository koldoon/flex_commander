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
  String heading(int i) => 'Раздел $i';

  // Абзацы и врезки разной высоты **нарочно**. На документе из одинаковых
  // блоков любая прикидка «доля от всей длины» попадает точно, и её промах не
  // увидела бы ни одна проверка.
  String paragraph(int i) => 'Текст раздела $i.${' Длинная добавка к абзацу.' * (i % 4)}';

  final tall = '```\n${List.generate(60, (n) => 'строка кода $n').join('\n')}\n```';

  final source = [
    for (var i = 0; i < 40; i++) '## ${heading(i)}\n\n${paragraph(i)}\n${i < 5 ? '\n$tall\n' : ''}',
  ].join('\n');

  final document = FcMarkdownDocument.parse(source);

  /// Первая видимая строка блока — по ней его и находят на экране.
  ///
  /// Считается по самому документу, а не по формуле «два блока на раздел»:
  /// врезки эту формулу и ломают, а проверка, считающая номера сама, врёт
  /// вместе с собой.
  final Map<int, String> firstLineOf = {};
  for (var line = document.blockOfLine.length - 1; line >= 0; line--) {
    firstLineOf[document.blockOfLine[line]] = document.plainText.split('\n')[line];
  }

  /// Номер блока, который начинается этой строкой.
  int blockOf(String text) => firstLineOf.entries.firstWhere((entry) => entry.value == text).key;

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
              child: FcMarkdownView(document: document, startAtBlock: startAtBlock, onTopBlock: onTopBlock),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('без просьбы документ открывается с начала', (tester) async {
    await pump(tester);

    expect(find.text(heading(0)), findsOneWidget);
    expect(find.text(heading(20)), findsNothing);
  });

  testWidgets('просили блок — он и стоит сверху', (tester) async {
    await pump(tester, startAtBlock: blockOf(heading(20)));

    final view = tester.getRect(find.byType(FcMarkdownView));

    expect(find.text(heading(20)), findsOneWidget);
    expect(find.text(heading(0)), findsNothing, reason: 'начало документа осталось выше');
    expect(tester.getRect(find.text(heading(20))).top, moreOrLessEquals(view.top, epsilon: 1));
  });

  testWidgets('место встаёт сразу, без плавной прокрутки', (tester) async {
    // Человек не просил никуда ехать — он переключил вид. Показ, который
    // едет сам, читается как чужое действие.
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
              child: FcMarkdownView(document: document, startAtBlock: blockOf(heading(20))),
            ),
          ),
        ),
      ),
    );
    // Один-единственный кадр: списку некуда ехать, он **начинается** с нужного
    // блока.
    await tester.pump();

    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final view = tester.getRect(find.byType(FcMarkdownView));

    expect(position.pixels, 0, reason: 'блок и есть точка отсчёта');
    expect(tester.getRect(find.text(heading(20))).top, moreOrLessEquals(view.top, epsilon: 1));

    // И времени вдоволь ничего не меняет: если бы показ куда-то ехал, он бы
    // доехал именно здесь.
    await tester.pump(const Duration(milliseconds: 500));

    expect(position.pixels, 0);
  });

  testWidgets('выше начального блока документ не обрывается', (tester) async {
    // Точка отсчёта — не начало списка: то, что выше, должно листаться.
    await pump(tester, startAtBlock: blockOf(heading(20)));

    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    expect(position.minScrollExtent, lessThan(0));

    // На экран вверх: предыдущий раздел обязан построиться и показаться.
    // Именно построиться — выше точки отсчёта список так же ленив, как ниже.
    position.jumpTo(-300);
    await tester.pumpAndSettle();

    expect(find.text(heading(19)), findsOneWidget);
  });

  testWidgets('докрутили — сказано, какой блок сверху', (tester) async {
    final seen = <int>[];
    await pump(tester, onTopBlock: seen.add);

    expect(seen, isEmpty, reason: 'пока не крутили — и говорить не о чем');

    // Прокруткой, а не перетаскиванием: клавиши и колесо ходят через неё же, а
    // перетаскивание внутри `SelectionArea` — это ещё и выделение.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(600);
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty);
    expect(seen.last, greaterThan(0));
  });

  testWidgets('названный блок — тот, что видно сверху', (tester) async {
    final seen = <int>[];
    await pump(tester, onTopBlock: seen.add);

    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // В конец документа: высокие врезки стоят в начале, и там сверху
    // оказывается строка кода — её рисует не подпись, по тексту не найти.
    // Прыжками, пока длина не перестанет расти: список ленив, и до конца он
    // доходит, только построив всё по дороге.
    for (var i = 0; i < 20 && position.pixels < position.maxScrollExtent; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    position.jumpTo(position.pixels - 400);
    await tester.pumpAndSettle();
    final int higher = seen.last;

    position.jumpTo(position.pixels + 400);
    await tester.pumpAndSettle();

    expect(seen.last, greaterThan(higher), reason: 'крутили вниз — и блок сверху стал дальше');

    // И названный блок правда стоит у верхней кромки, а не просто «какой-то из
    // построенных».
    final view = tester.getRect(find.byType(FcMarkdownView));
    final block = tester.getRect(find.text(firstLineOf[seen.last]!));

    expect(block.bottom, greaterThan(view.top), reason: 'названный блок уже уехал вверх');
    expect(block.top, lessThan(view.top + view.height / 3));
  });
}
