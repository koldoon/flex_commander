import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
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
}
