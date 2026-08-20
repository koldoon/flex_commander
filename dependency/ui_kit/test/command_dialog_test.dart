import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Содержимое окна команды.
void main() {
  const metrics = DefaultMetrics();

  Future<void> pump(WidgetTester tester, List<Widget> children, {String? error}) async {
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
              child: CommandDialogForm(
                onCancel: () {},
                onSubmit: () {},
                submitLabel: 'Do',
                error: error,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpProgress(WidgetTester tester, {String? stageLabel}) async {
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
              child: CommandDialogProgress(
                message: 'Copying notes.txt…',
                stageLabel: stageLabel,
                processed: 3,
                total: 10,
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('этап показан отдельной строкой', (tester) async {
    // Он объясняет, почему счёт объектов уже полон, а работа идёт.
    await pumpProgress(tester, stageLabel: '2 of 2 — repacking archive');

    expect(find.text('Stage'), findsOneWidget);
    expect(find.text('2 of 2 — repacking archive'), findsOneWidget);
  });

  testWidgets('у одноплечей работы строки этапа нет вовсе', (tester) async {
    // Большинство работ одноплечие, и лишняя строка в их окне ничего не
    // сообщает.
    await pumpProgress(tester);

    expect(find.text('Stage'), findsNothing);
  });

  testWidgets('строки окна разделены общим зазором', (tester) async {
    // Иначе каждое окно расставляет его вручную, а забывшее — слепляет поля
    // друг с другом: ровно так и вышло с окном поиска.
    await pump(tester, const [
      CommandDialogField(label: 'One', child: SizedBox(height: 24)),
      FcCheckbox(label: 'Two', value: false, onChanged: null),
      FcCheckbox(label: 'Three', value: false, onChanged: null),
    ]);

    final first = tester.getRect(find.byType(CommandDialogField));
    final checkboxes = tester.widgetList<FcCheckbox>(find.byType(FcCheckbox)).toList();
    final second = tester.getRect(find.byWidget(checkboxes[0]));
    final third = tester.getRect(find.byWidget(checkboxes[1]));

    expect(second.top - first.bottom, closeTo(metrics.dialogGap, 0.01));
    expect(third.top - second.bottom, closeTo(metrics.dialogGap, 0.01));
  });

  testWidgets('сообщение об ошибке отделено тем же зазором', (tester) async {
    await pump(tester, const [CommandDialogField(label: 'One', child: SizedBox(height: 24))], error: 'не вышло');

    final field = tester.getRect(find.byType(CommandDialogField));
    final message = tester.getRect(find.text('не вышло'));

    expect(message.top - field.bottom, closeTo(metrics.dialogGap, 0.01));
  });
}
