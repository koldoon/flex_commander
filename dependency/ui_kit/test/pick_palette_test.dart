import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно-палитра в порядке строк — так его открывает оглавление PDF
/// (`docs/spec/pdf-viewer.md`, §16.1).
void main() {
  const rows = [
    FcPickRow(id: 'a', title: 'Introduction'),
    FcPickRow(id: 'b', title: 'Getting started', indent: 1),
    FcPickRow(id: 'c', title: 'Reference'),
    FcPickRow(id: 'd', title: 'Index'),
  ];

  late List<String> picked;

  Future<void> pump(WidgetTester tester, {String? initial}) async {
    picked = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: FcPickPalette(rows: rows, hint: 'Chapter', keepOrder: true, initial: initial, onPick: picked.add),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> shown(WidgetTester tester) =>
      tester.widget<FcPickList>(find.byType(FcPickList)).rows.map((row) => row.id).toList();

  testWidgets('отбор прячет неподходящее, порядок остаётся порядком строк', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'in');
    await tester.pump();

    // По весу совпадения «Index» встал бы первым: «in» у него в начале имени.
    expect(shown(tester), ['a', 'b', 'd']);
  });

  testWidgets('открывается на заданной строке, и Enter выбирает её', (tester) async {
    await pump(tester, initial: 'c');

    expect(tester.widget<FcPickList>(find.byType(FcPickList)).selected, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, ['c']);
  });

  testWidgets('вложенный заголовок стоит правее', (tester) async {
    await pump(tester);

    final top = tester.getTopLeft(find.text('Introduction')).dx;
    final nested = tester.getTopLeft(find.text('Getting started')).dx;
    expect(nested, greaterThan(top));
  });
}
