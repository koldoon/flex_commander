import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно настройки клавиш (`docs/spec/key-bindings.md`).
void main() {
  late AppRuntime runtime;

  // Платформа в виджетных тестах не macOS, поэтому «командная» клавиша здесь
  // `Ctrl`: ровно то, во что `KeyCombination` сворачивает `Cmd` вне macOS.
  const commandKey = LogicalKeyboardKey.control;

  setUp(() async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
      ..home = '/home';
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    runtime = await testApp(provider: provider, modules: featureModules(), settings: settings);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [],
  }) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pumpAndSettle();
  }

  /// Открыть окно так, как его открывает кнопка настроек.
  Future<void> openWindow(WidgetTester tester) async {
    expect(runtime.commands.run('app.keys'), isTrue, reason: 'окно не открылось');
    await tester.pumpAndSettle();
  }

  /// Открыть окно и отобрать строку по названию команды.
  Future<void> openFor(WidgetTester tester, String query) async {
    await openWindow(tester);
    expect(find.byType(FcKeyBindings), findsOneWidget, reason: 'окно не открылось');
    // Поле именно окна: внизу приложения стоит командная строка, и она тоже
    // `TextField`.
    await tester.enterText(find.descendant(of: find.byType(FcKeyBindings), matching: find.byType(TextField)), query);
    await tester.pumpAndSettle();
  }

  String? keysOf(String commandId) => runtime.commands.bindingsOf(commandId).firstOrNull?.keys.toString();

  testWidgets('кнопка в настройках открывает окно клавиш', (tester) async {
    // Своей клавиши у окна нет: открывают его отсюда и из палитры
    // (`docs/spec/key-bindings.md`, §7).
    await pumpApp(tester);

    await press(tester, LogicalKeyboardKey.f9);
    expect(find.text('Key bindings'), findsOneWidget, reason: 'кнопки в настройках нет');

    await tester.tap(find.widgetWithText(FcButton, 'Key bindings'));
    await tester.pumpAndSettle();

    expect(find.byType(FcKeyBindings), findsOneWidget);
    // Первая же строка говорит, чем команда вызывается.
    expect(find.text('F5'), findsWidgets, reason: 'клавиш в списке не видно');
  });

  testWidgets('Enter начинает захват, нажатие назначает клавишу', (tester) async {
    await pumpApp(tester);
    await openFor(tester, 'file.copy');

    await press(tester, LogicalKeyboardKey.enter);
    expect(find.textContaining('Press the combination'), findsOneWidget, reason: 'окно не сказало, что ждёт нажатия');

    await press(tester, LogicalKeyboardKey.keyY, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

    expect(keysOf('file.copy'), 'Ctrl-Shift-Y');
    expect(runtime.app.keyOverrides.single.was, 'F5', reason: 'привязка опознаётся прежней клавишей');
  });

  testWidgets('Esc отменяет захват, ничего не меняя', (tester) async {
    await pumpApp(tester);
    await openFor(tester, 'file.copy');

    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.escape);

    expect(find.byType(FcKeyBindings), findsOneWidget, reason: 'Esc закрыл окно вместо отмены захвата');
    expect(keysOf('file.copy'), 'F5');
    expect(runtime.app.keyOverrides, isEmpty);
  });

  testWidgets('занятая клавиша спрашивает, у кого её отнять', (tester) async {
    await pumpApp(tester);
    await openFor(tester, 'file.copy');

    await press(tester, LogicalKeyboardKey.enter);
    // `F6` в панели держит перенос — то же место, значит спор.
    await press(tester, LogicalKeyboardKey.f6);

    expect(find.textContaining('belongs to'), findsOneWidget, reason: 'о столкновении промолчали');
    expect(keysOf('file.copy'), 'F5', reason: 'клавишу назначили, не спросив');

    await press(tester, LogicalKeyboardKey.enter);

    expect(keysOf('file.copy'), 'F6');
    expect(keysOf('file.move'), '', reason: 'у прежнего держателя клавиша осталась');
  });

  testWidgets('Esc на вопросе оставляет всё как было', (tester) async {
    await pumpApp(tester);
    await openFor(tester, 'file.copy');

    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.f6);
    await press(tester, LogicalKeyboardKey.escape);

    expect(keysOf('file.copy'), 'F5');
    expect(keysOf('file.move'), 'F6');
  });

  testWidgets('Bsp снимает клавишу, Cmd-R возвращает умолчание', (tester) async {
    await pumpApp(tester);
    await openFor(tester, 'file.copy');

    await press(tester, LogicalKeyboardKey.backspace);
    expect(keysOf('file.copy'), '', reason: 'клавиша не снялась');

    await press(tester, LogicalKeyboardKey.keyR, modifiers: const [commandKey]);
    expect(keysOf('file.copy'), 'F5');
    expect(runtime.app.keyOverrides, isEmpty, reason: 'умолчание не должно оставаться записью');
  });

  testWidgets('«Reset all» возвращает все умолчания', (tester) async {
    await pumpApp(tester);
    await openFor(tester, 'file.copy');
    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.keyY, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);
    expect(runtime.app.keyOverrides, isNotEmpty);

    await tester.tap(find.widgetWithText(FcButton, 'Reset all'));
    await tester.pumpAndSettle();

    expect(runtime.app.keyOverrides, isEmpty);
    expect(keysOf('file.copy'), 'F5');
  });
}
