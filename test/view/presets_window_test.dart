import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Раздел «Presets» в окне настроек (`docs/spec/settings-presets.md`, §6).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  /// Открыть настройки и отобрать раздел наборов: так до него не надо
  /// долистывать.
  Future<void> openPresets(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(of: find.byType(FcSettingsForm), matching: find.byType(TextField)).first,
      'preset',
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FcButton, label));
    await tester.pumpAndSettle();
  }

  /// Набрать имя в окне и подтвердить.
  Future<void> nameIt(WidgetTester tester, String name) async {
    await tester.enterText(find.descendant(of: find.byType(CommandDialogForm), matching: find.byType(TextField)), name);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save the set');
  }

  testWidgets('раздел зовётся по делу, а не именем модуля', (tester) async {
    await openPresets(tester);

    expect(find.text('Presets'), findsWidgets);
  });

  testWidgets('набор складывается и сразу виден в списке', (tester) async {
    await openPresets(tester);
    expect(find.text('None'), findsWidgets, reason: 'пустой выбор должен быть настоящим вариантом');

    await tapButton(tester, 'Save as new…');
    await nameIt(tester, 'Дом');

    expect(runtime.app.presets.single.name, 'Дом');
    expect(runtime.app.preset, 'Дом');
    // Схемы строятся один раз, и без пересборки нового набора в списке бы не
    // было (`docs/spec/settings-presets.md`, §6).
    expect(find.text('Дом'), findsWidgets, reason: 'набор не появился, не закрывая окна');
  });

  testWidgets('занятое имя — ошибка в том же окне', (tester) async {
    await openPresets(tester);
    await tapButton(tester, 'Save as new…');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'Save as new…');
    await nameIt(tester, 'Дом');

    expect(find.text('There is a set with this name already'), findsOneWidget);
    expect(runtime.app.presets, hasLength(1), reason: 'второй «Дом» затёр бы первый');
  });

  testWidgets('без выбранного набора обновлять и удалять нечего', (tester) async {
    await openPresets(tester);

    // Приглушены, а не спрятаны: действие есть, просто сейчас неприменимо.
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Update')).onPressed, isNull);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Delete')).onPressed, isNull);
  });

  testWidgets('кнопки называют выбранный набор', (tester) async {
    await openPresets(tester);
    await tapButton(tester, 'Save as new…');
    await nameIt(tester, 'Дом');

    expect(find.widgetWithText(FcButton, 'Update «Дом»'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'Delete «Дом»'), findsOneWidget);
  });

  testWidgets('удаление спрашивает и убирает набор', (tester) async {
    await openPresets(tester);
    await tapButton(tester, 'Save as new…');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'Delete «Дом»');
    expect(find.text('Delete «Дом»? Settings stay as they are.'), findsOneWidget);
    await tapButton(tester, 'Delete');

    expect(runtime.app.presets, isEmpty);
    expect(runtime.app.preset, isEmpty);
  });

  testWidgets('отказ ничего не убирает', (tester) async {
    await openPresets(tester);
    await tapButton(tester, 'Save as new…');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'Delete «Дом»');
    await tapButton(tester, 'Cancel');

    expect(runtime.app.presets, hasLength(1));
  });
}
