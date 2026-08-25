import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flex_commander/view/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно команды заполняется с клавиатуры: `Tab` обходит его элементы, `Space`
/// нажимает, стрелки ходят по переключателю.
///
/// Проверяется рама вместе с контролами: обход — это их общее свойство, и
/// поодиночке его не увидеть.
const _theme = FcThemeSpec(
  id: 'default',
  title: 'Default',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

void main() {
  late TextEditingController text;
  late bool checked;
  late String choice;
  late List<String> pressed;
  late int submits;
  late int dismisses;

  setUp(() {
    text = TextEditingController();
    checked = false;
    choice = 'normal';
    pressed = [];
    submits = 0;
    dismisses = 0;
  });

  tearDown(() => text.dispose());

  Future<void> pumpDialog(WidgetTester tester, {bool withDisabled = true}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(_theme),
        home: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, setState) => DialogFrame(
                  title: 'Copy',
                  takesFocus: true,
                  onSubmit: () => submits++,
                  onDismiss: () => dismisses++,
                  child: CommandDialogForm(
                    submitLabel: 'Copy',
                    onCancel: () => pressed.add('Cancel'),
                    onSubmit: () => pressed.add('Copy'),
                    children: [
                      if (withDisabled)
                        CommandDialogField(
                          label: 'From',
                          child: FcTextField(controller: TextEditingController(text: '/home'), enabled: false),
                        ),
                      CommandDialogField(label: 'To', child: FcTextField(controller: text, autofocus: true)),
                      FcCheckbox(
                        label: 'Follow symlinks',
                        value: checked,
                        onChanged: (value) => setState(() => checked = value),
                      ),
                      CommandDialogField(
                        label: 'Compression',
                        child: FcRadioGroup<String>(
                          options: const {'store': 'Store', 'normal': 'Normal', 'max': 'Max'},
                          value: choice,
                          onChanged: (value) => setState(() => choice = value),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Future<void> tab(WidgetTester tester, {bool back = false}) async {
    if (back) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (back) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    }
    await tester.pumpAndSettle();
  }

  /// Что сейчас в фокусе — по типу виджета, которому принадлежит узел.
  Type? focusedType() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) {
      return null;
    }
    for (final type in [FcTextField, FcCheckbox, FcRadioGroup<String>, FcButton]) {
      final found = find.ancestor(of: find.byWidget(context.widget), matching: find.byType(type));
      if (found.evaluate().isNotEmpty) {
        return type;
      }
    }
    return context.widget.runtimeType;
  }

  testWidgets('Tab обходит элементы окна по порядку и возвращается к первому', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    // Поле ввода взяло фокус само: команда сказала `takesFocus`.
    expect(focusedType(), FcTextField);

    await tab(tester);
    expect(focusedType(), FcCheckbox);

    await tab(tester);
    expect(focusedType(), FcRadioGroup<String>, reason: 'переключатель — одна остановка, а не три');

    await tab(tester);
    expect(focusedType(), FcButton, reason: 'Cancel');

    await tab(tester);
    expect(focusedType(), FcButton, reason: 'подтверждение');

    // Круг замкнулся: за окном панели, и наружу обход не выходит.
    await tab(tester);
    expect(focusedType(), FcTextField);
  });

  testWidgets('Shift-Tab идёт в обратную сторону', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await tab(tester, back: true);
    expect(focusedType(), FcButton, reason: 'назад с поля — на кнопку подтверждения');

    await tab(tester, back: true);
    expect(focusedType(), FcButton);

    await tab(tester, back: true);
    expect(focusedType(), FcRadioGroup<String>);
  });

  testWidgets('выключенное поле обход пропускает', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    // Полей два, но «откуда» выключено — обход его не касается вовсе.
    final seen = <Type?>[];
    for (var i = 0; i < 5; i++) {
      seen.add(focusedType());
      await tab(tester);
    }

    expect(seen.where((type) => type == FcTextField), hasLength(1));
  });

  testWidgets('Space переключает флажок', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();
    await tab(tester);
    expect(focusedType(), FcCheckbox);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(checked, isTrue);
  });

  testWidgets('Space нажимает кнопку', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();
    await tab(tester, back: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(pressed, ['Copy'], reason: 'нажали ту кнопку, на которой стоял фокус');
    expect(submits, 0, reason: 'подтверждение окна тут ни при чём');
  });

  testWidgets('Enter на кнопке нажимает её, а не подтверждает окно', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();
    await tab(tester, back: true);
    expect(focusedType(), FcButton);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Иначе человек, дотабившийся до кнопки, получил бы не её, а подтверждение
    // окна — то самое «Overwrite» вместо «Cancel».
    expect(pressed, ['Copy']);
    expect(submits, 0);
  });

  testWidgets('Enter в поле ввода по-прежнему подтверждает окно', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();
    expect(focusedType(), FcTextField);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(submits, 1);
    expect(pressed, isEmpty);
  });

  testWidgets('Esc закрывает окно откуда угодно, включая кнопку', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dismisses, 1, reason: 'из поля ввода');

    await tab(tester, back: true);
    expect(focusedType(), FcButton);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(dismisses, 2, reason: 'и с кнопки: Esc — это выход, он не зависит от фокуса');
  });

  testWidgets('стрелки ходят по переключателю и не уводят фокус наружу', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();
    await tab(tester);
    await tab(tester);
    expect(focusedType(), FcRadioGroup<String>);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(choice, 'max');

    // По кругу: за последним снова первый.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(choice, 'store');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(choice, 'max');

    expect(focusedType(), FcRadioGroup<String>, reason: 'стрелка не выводит из группы');
  });
}
