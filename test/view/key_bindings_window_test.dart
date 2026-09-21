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
    expect(find.byType(FcSettingsForm), findsOneWidget, reason: 'окна клавиш нет');
  }

  /// Набрать запрос в поиске **окна клавиш**, а не в командной строке внизу.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.descendant(of: find.byType(FcSettingsForm), matching: find.byType(TextField)).first,
      query,
    );
    await tester.pumpAndSettle();
  }

  /// Найти в **окне клавиш**, а не во всём приложении: за окном стоит ряд
  /// функциональных кнопок, и «Copy» написано и там.
  Finder inWindow(Finder what) => find.descendant(of: find.byType(FcSettingsForm), matching: what);

  /// Открыть окошко записи у строки, отобранной запросом.
  Future<void> openRecorder(WidgetTester tester, String query, String keys) async {
    await openWindow(tester);
    await search(tester, query);
    await tester.tap(inWindow(find.widgetWithText(FcButton, keys)));
    await tester.pumpAndSettle();
    expect(find.byType(FcKeyRecorder), findsOneWidget, reason: 'окошко записи не открылось');
  }

  String? keysOf(String commandId) => runtime.commands.bindingsOf(commandId).firstOrNull?.keys.toString();

  testWidgets('кнопка в настройках открывает окно клавиш', (tester) async {
    // Своей клавиши у окна нет: открывают его отсюда и из палитры
    // (`docs/spec/key-bindings.md`, §1).
    await pumpApp(tester);

    await press(tester, LogicalKeyboardKey.f9);
    expect(find.text('Keymap'), findsOneWidget, reason: 'кнопки в настройках нет');

    await tester.tap(find.widgetWithText(FcButton, 'Keymap'));
    await tester.pumpAndSettle();

    expect(runtime.app.view.dialogs, hasLength(2), reason: 'окно клавиш должно встать поверх настроек');
    expect(
      find.descendant(of: find.byType(FcSettingsForm), matching: find.text('File panels')),
      findsWidgets,
      reason: 'разделов по контексту не видно',
    );
  });

  testWidgets('команда стоит в своём разделе ровно один раз', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, 'file.copy');

    expect(inWindow(find.widgetWithText(FcButton, 'F5')), findsOneWidget);
    // Рядом только «Copy path» — другая команда, и клавиша у неё своя. Третья
    // кнопка — «вернуть всё» в подвале оглавления: она стоит всегда.
    expect(inWindow(find.byType(FcButton)), findsNWidgets(3));
  });

  testWidgets('дважды объявленный Esc просмотрщика не даёт двух строк', (tester) async {
    // `viewer.close` объявлен четырьмя привязками — `Esc` и `F10`, каждая для
    // полного экрана и для быстрого просмотра. Это одно дело и одна строка.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, 'viewer.close');

    expect(
      inWindow(find.byType(FcButton)),
      findsOneWidget,
      reason: 'закрытие просмотрщика — поведение, а не настройка; кнопка остаётся только в подвале',
    );
  });

  testWidgets('поиск в панели и в редакторе стоят в разных разделах', (tester) async {
    // Две команды с одинаковыми названием и описанием: `text.find` и
    // `editor.find`. Разводит их раздел.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, 'Find text in the document');

    expect(inWindow(find.text('Text viewer')), findsWidgets);
    expect(inWindow(find.text('Text editor')), findsWidgets);
  });

  testWidgets('ищется по синонимам команды', (tester) async {
    // «Switch theme» ищут словом `dark`, которого в подписи нет вовсе.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, 'dark');

    expect(inWindow(find.widgetWithText(FcButton, '—')), findsOneWidget, reason: 'клавиши у неё нет, и это видно');
    expect(find.text('Switch theme'), findsWidgets, reason: 'нашлась не та команда');
  });

  testWidgets('Record назначает клавишу и показывает её тут же', (tester) async {
    await pumpApp(tester);
    await openRecorder(tester, 'file.copy', 'F5');

    await tester.tap(find.widgetWithText(FcButton, 'Record'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyY, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

    expect(keysOf('file.copy'), 'Ctrl-Shift-Y');
    // Клавиша читается замыканием, поэтому новая видна, не закрывая окошка.
    expect(find.descendant(of: find.byType(FcKeyRecorder), matching: find.text('Ctrl-Shift-Y')), findsOneWidget);
  });

  testWidgets('Esc отменяет ожидание, ничего не меняя', (tester) async {
    await pumpApp(tester);
    await openRecorder(tester, 'file.copy', 'F5');

    await tester.tap(find.widgetWithText(FcButton, 'Record'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.escape);

    expect(keysOf('file.copy'), 'F5');
    expect(find.byType(FcKeyRecorder), findsOneWidget, reason: 'Esc отменил ожидание, а не закрыл окошко');
  });

  testWidgets('занятая клавиша спрашивает, у кого её отнять', (tester) async {
    await pumpApp(tester);
    await openRecorder(tester, 'file.copy', 'F5');

    await tester.tap(find.widgetWithText(FcButton, 'Record'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.f6);

    expect(
      find.descendant(of: find.byType(FcKeyRecorder), matching: find.textContaining('Move')),
      findsOneWidget,
      reason: 'не сказано, у кого клавиша',
    );
    expect(keysOf('file.copy'), 'F5', reason: 'пока не ответили, ничего не меняется');

    await tester.tap(find.widgetWithText(FcButton, 'Take the key'));
    await tester.pumpAndSettle();

    expect(keysOf('file.copy'), 'F6');
    expect(keysOf('file.move'), isEmpty, reason: 'у прежней клавиша снята');
  });

  testWidgets('«Оставить» не трогает ничего', (tester) async {
    await pumpApp(tester);
    await openRecorder(tester, 'file.copy', 'F5');

    await tester.tap(find.widgetWithText(FcButton, 'Record'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.f6);
    await tester.tap(find.widgetWithText(FcButton, 'Leave it'));
    await tester.pumpAndSettle();

    expect(keysOf('file.copy'), 'F5');
    expect(keysOf('file.move'), 'F6');
  });

  testWidgets('Clear снимает клавишу, Reset возвращает умолчание', (tester) async {
    await pumpApp(tester);
    await openRecorder(tester, 'file.copy', 'F5');

    await tester.tap(find.widgetWithText(FcButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(keysOf('file.copy'), isEmpty);

    await tester.tap(find.widgetWithText(FcButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(keysOf('file.copy'), 'F5');
  });

  testWidgets('команде без клавиши клавишу можно дать', (tester) async {
    await pumpApp(tester);
    await openRecorder(tester, 'dark', '—');

    await tester.tap(find.widgetWithText(FcButton, 'Record'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyD, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

    expect(keysOf('app.theme.use'), 'Ctrl-Shift-D');
  });

  testWidgets('подвал остаётся внизу, когда ничего не нашлось', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    final bottom = tester.getBottomLeft(inWindow(find.widgetWithText(FcButton, 'Reset all keys'))).dy;
    await search(tester, 'такой команды нет');

    expect(find.text('Nothing found'), findsOneWidget);
    expect(
      tester.getBottomLeft(inWindow(find.widgetWithText(FcButton, 'Reset all keys'))).dy,
      bottom,
      reason: 'подвал убежал наверх',
    );
  });

  testWidgets('«Reset all keys» возвращает все умолчания', (tester) async {
    await pumpApp(tester);
    runtime.app.setKeyOverrides([KeyOverride(command: 'file.copy', was: 'F5', now: 'Ctrl-Shift-Y')]);
    await openWindow(tester);

    // Кнопка стоит в подвале оглавления и отбором не пропадает.
    await search(tester, 'file.copy');
    await tester.tap(inWindow(find.widgetWithText(FcButton, 'Reset all keys')));
    await tester.pumpAndSettle();

    expect(runtime.app.keyOverrides, isEmpty);
    expect(keysOf('file.copy'), 'F5');
  });
}
