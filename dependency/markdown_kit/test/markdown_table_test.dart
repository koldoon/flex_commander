import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('линейки таблицы — цветом разделителя колонок панели', () {
    final colors = DefaultColors();
    final theme = FcTheme(colors: colors, metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts());

    final border = fcMarkdownStyle(theme).tableBorder!;

    expect(border.top.color, colors.columnDivider);
    expect(border.horizontalInside.color, colors.columnDivider);
  });

  test('текст в ячейках — слева направо и сверху вниз', () {
    final theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    final style = fcMarkdownStyle(theme);

    expect(style.tableHeadAlign, TextAlign.left);
    expect(style.tableVerticalAlignment, TableCellVerticalAlignment.top);
  });

  test('углы таблицы скруглены тем же радиусом, что и врезка', () {
    // Таблица и врезка — оба «вставленный кусок». Острые углы у одного при
    // скруглённых у другого читаются как небрежность.
    final theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    final radius = fcMarkdownStyle(theme).tableBorder!.borderRadius;

    expect(radius, isNot(BorderRadius.zero));
    expect(radius, fcCodeBlockDecoration(theme).borderRadius);
  });

  testWidgets('текст в ячейках не липнет к линейкам', (tester) async {
    // Тем же отступом, что и у врезки: с прежним текст стоял вплотную.
    final theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [theme]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 300,
              child: FcMarkdownView(
                document: FcMarkdownDocument.parse('| Ключ | Что делает |\n|---|---|\n| `F3` | показать |\n'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final left = tester.getRect(find.text('Ключ'));
    final right = tester.getRect(find.text('Что делает'));

    // Между подписями соседних колонок — два поля и линейка между ними.
    expect(right.left - left.right, greaterThanOrEqualTo(theme.metrics.dialogPadding * 2));
  });

  testWidgets('ширина колонки — по её содержимому, а не поровну', (tester) async {
    // Колонка «Да/Нет» и колонка с описанием на три строки не должны получать
    // поровну: одна стоит полупустой, другая переносится впятеро чаще нужного.
    final theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    const source =
        '| Клавиша | Что она делает и почему именно так | Своя |\n'
        '|---|---|---|\n'
        '| F3 | Открывает просмотрщик для того, что под курсором, и выбирает его по содержимому | Да |\n'
        '| F4 | Правит | Нет |\n';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [theme]),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 600, height: 400, child: FcMarkdownView(document: FcMarkdownDocument.parse(source))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ячейки первой строки — это и есть ширины колонок.
    final cells = [for (var i = 0; i < 3; i++) tester.getRect(find.byType(TableCell).at(i)).width];

    expect(cells[1], greaterThan(cells[0]), reason: 'описание шире клавиши');
    expect(cells[0], greaterThan(cells[2]), reason: 'клавиша шире, чем «Да/Нет»');
    expect(cells[2], lessThan(600 / 3), reason: 'поровну было бы 200');
    expect(cells[1], greaterThan(600 / 3), reason: 'описание забирает то, что не нужно соседям');

    // И таблица по-прежнему укладывается в отведённую ширину: длинный текст
    // переносится, а не уезжает вбок.
    expect(cells.reduce((a, b) => a + b), lessThanOrEqualTo(600));
  });

  testWidgets('узкую колонку не сжимают уже её содержимого', (tester) async {
    // Сжать ниже самого длинного слова нельзя: оно порвётся.
    final theme = FcTheme(
      colors: DefaultColors(),
      metrics: DefaultMetrics(),
      icons: DefaultIcons(),
      fonts: DefaultFonts(),
    );

    final source =
        '| Очень длинное описание, которое заведомо не влезает в отведённое место и переносится | Своя |\n'
        '|---|---|\n'
        '| ${'слово ' * 40} | Да |\n';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [theme]),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 400, height: 600, child: FcMarkdownView(document: FcMarkdownDocument.parse(source))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final narrow = tester.getRect(find.byType(TableCell).at(1));
    final label = tester.getRect(find.text('Своя'));

    expect(narrow.width, greaterThanOrEqualTo(label.width));
    expect(label.height, lessThan(32), reason: 'подпись не разорвало переносом');
  });
}
