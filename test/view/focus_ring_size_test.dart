import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/view/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = FcThemeSpec(
  id: 'default',
  title: 'Default',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

/// Обводка фокуса не меняет размеров: она рисуется поверх, а не рамкой.
void main() {
  testWidgets('кнопка не растёт от фокуса', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(_theme),
        home: Scaffold(body: Center(child: FcButton(label: 'Copy', onPressed: () {}, focusNode: node))),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(FcButton));

    node.requestFocus();
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(FcButton));

    expect(after, before, reason: 'кнопка от обводки не раздаётся');
  });

  testWidgets('поле ввода не растёт от фокуса', (tester) async {
    final node = FocusNode();
    final controller = TextEditingController(text: '/home');
    addTearDown(node.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(_theme),
        home: Scaffold(
          body: Center(child: IntrinsicWidth(child: FcTextField(controller: controller, focusNode: node))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(FcTextField));

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FcTextField)), before);
  });

  testWidgets('флажок не растёт от фокуса', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(_theme),
        home: Scaffold(
          body: Center(child: FcCheckbox(label: 'Follow symlinks', value: false, onChanged: (_) {}, focusNode: node)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(FcCheckbox));

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FcCheckbox)), before);
  });

  testWidgets('переключатель не растёт от фокуса', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildThemeData(_theme),
        home: Scaffold(
          body: Center(
            child: FcRadioGroup<String>(
              options: const {'store': 'Store', 'normal': 'Normal'},
              value: 'normal',
              onChanged: (_) {},
              focusNode: node,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(FcRadioGroup<String>));

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FcRadioGroup<String>)), before);
  });
}
