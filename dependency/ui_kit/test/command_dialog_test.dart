import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Содержимое окна команды.
void main() {
  const metrics = DefaultMetrics();

  Future<void> pump(WidgetTester tester, List<CommandDialogField> children, {String? error}) async {
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
      CommandDialogField(label: 'One', child: SizedBox(key: ValueKey('one'), height: 24)),
      CommandDialogField.wide(child: SizedBox(key: ValueKey('two'), height: 24)),
      CommandDialogField.wide(child: SizedBox(key: ValueKey('three'), height: 24)),
    ]);

    // Меряется содержимое строк, а не подписи: подпись стоит по середине своей
    // строки, и расстояние от неё до соседней зависит от высоты содержимого.
    final first = tester.getRect(find.byKey(const ValueKey('one')));
    final second = tester.getRect(find.byKey(const ValueKey('two')));
    final third = tester.getRect(find.byKey(const ValueKey('three')));

    // Над строкой без подписи просвет свой и больше: она стоит **под** полями,
    // а не в их ряду, и с общим зазором читалась бы как ещё одно поле, у
    // которого забыли подпись.
    expect(second.top - first.bottom, closeTo(metrics.dialogWideRowGap, 0.01));
    expect(third.top - second.bottom, closeTo(metrics.dialogWideRowGap, 0.01));
  });

  testWidgets('строка без подписи отбита с обеих сторон, а не только сверху', (tester) async {
    // Иначе флажок висит близко к строке под собой и читается как её часть:
    // в окне упаковки «Follow symlinks» прижимался к «Compression».
    await pump(tester, const [
      CommandDialogField(label: 'One', child: SizedBox(key: ValueKey('one'), height: 24)),
      CommandDialogField.wide(child: SizedBox(key: ValueKey('two'), height: 24)),
      CommandDialogField(label: 'Three', child: SizedBox(key: ValueKey('three'), height: 24)),
    ]);

    final first = tester.getRect(find.byKey(const ValueKey('one')));
    final second = tester.getRect(find.byKey(const ValueKey('two')));
    final third = tester.getRect(find.byKey(const ValueKey('three')));

    expect(second.top - first.bottom, closeTo(metrics.dialogWideRowGap, 0.01));
    expect(third.top - second.bottom, closeTo(metrics.dialogWideRowGap, 0.01), reason: 'снизу столько же');
  });

  testWidgets('строка без подписи начинается там, где значения', (tester) async {
    // В референсе флаг стоит под полем ввода, а не под его подписью: у левого
    // края он читается как что-то отдельное от формы.
    await pump(tester, const [
      CommandDialogField(label: 'One', child: SizedBox(key: ValueKey('one'), height: 24)),
      CommandDialogField.wide(child: SizedBox(key: ValueKey('two'), height: 24)),
    ]);

    final field = tester.getRect(find.byKey(const ValueKey('one')));
    final flag = tester.getRect(find.byKey(const ValueKey('two')));

    expect(flag.left, closeTo(field.left, 0.01));
  });

  testWidgets('сообщение об ошибке отделено просветом строки без подписи', (tester) async {
    await pump(tester, const [
      CommandDialogField(label: 'One', child: SizedBox(key: ValueKey('one'), height: 24)),
    ], error: 'не вышло');

    final field = tester.getRect(find.byKey(const ValueKey('one')));
    final message = tester.getRect(find.text('не вышло'));

    expect(message.top - field.bottom, closeTo(metrics.dialogWideRowGap, 0.01));
    expect(message.left, closeTo(field.left, 0.01));
  });
}
