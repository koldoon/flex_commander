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
}
