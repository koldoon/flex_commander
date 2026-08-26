import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Столбец подписей — по самой широкой из них, а не по числу из темы.
void main() {
  Future<void> pumpForm(WidgetTester tester, List<String> labels) => pumpScreen(
    tester,
    CommandDialogBody(
      actions: const [],
      children: [for (final label in labels) CommandDialogField(label: label, child: const SizedBox(height: 20))],
    ),
  );

  testWidgets('все подписи в столбце одной ширины — по самой широкой', (tester) async {
    await pumpForm(tester, ['To', 'Compression']);

    final short = tester.getSize(find.text('To')).width;
    final long = tester.getSize(find.text('Compression')).width;

    expect(short, long, reason: 'столбец один на всю форму');
    // И он не шире, чем нужно: короткая форма не должна зиять пустотой слева.
    expect(long, lessThanOrEqualTo(FcTheme.of(tester.element(find.text('To'))).metrics.dialogLabelMaxWidth));

    await disposeScreen(tester);
  });

  testWidgets('столбец не шире меры из темы: длинная подпись переносится сама', (tester) async {
    // Без предела одна длинная подпись съедала бы форму: столбец растягивался
    // под неё, а значения ужимались в остаток и переносились по слову.
    await pumpForm(tester, ['To', 'Show progress inside a file from']);

    final metrics = FcTheme.of(tester.element(find.text('To'))).metrics;
    final column = tester.getSize(find.text('To')).width;

    expect(column, lessThanOrEqualTo(metrics.dialogLabelMaxWidth));
    // А длинная подпись живёт в двух строках вместо того, чтобы двигать форму.
    expect(
      tester.getSize(find.text('Show progress inside a file from')).height,
      greaterThan(tester.getSize(find.text('To')).height),
    );

    await disposeScreen(tester);
  });

  testWidgets('несколько форм с общей мерой выглядят одной', (tester) async {
    // Разделы окна настроек лежат порознь — между ними заголовки во всю
    // ширину, — но столбец подписей у них обязан быть один.
    late double measured;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) {
          measured = widestLabel(context, ['To', 'Compression']);
          return Column(
            children: [
              FcForm(
                labelWidth: measured,
                rows: const [CommandDialogField(label: 'To', child: SizedBox(key: ValueKey('first'), height: 20))],
              ),
              const Text('Заголовок раздела'),
              FcForm(
                labelWidth: measured,
                rows: const [
                  CommandDialogField(label: 'Compression', child: SizedBox(key: ValueKey('second'), height: 20)),
                ],
              ),
            ],
          );
        },
      ),
    );

    // Проверяется то, что видно: значения обоих разделов начинаются на одной
    // черте, хотя подписи у них разной длины.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('first'))).dx,
      tester.getTopLeft(find.byKey(const ValueKey('second'))).dx,
    );
    expect(measured, greaterThan(0));

    await disposeScreen(tester);
  });

  testWidgets('короткие подписи дают узкий столбец', (tester) async {
    await pumpForm(tester, ['To', 'From']);
    final narrow = tester.getSize(find.text('To')).width;

    await pumpForm(tester, ['To', 'Show progress inside a file from']);
    final wide = tester.getSize(find.text('To')).width;

    expect(narrow, lessThan(wide));

    await disposeScreen(tester);
  });
}
