import 'package:fc_api/fc_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно истории (`docs/spec/operation-history.md`, §10).
void main() {
  late AppRuntime runtime;
  late InMemoryTreeProvider provider;

  Future<void> open(WidgetTester tester) async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.txt', size: 20),
      FakeEntry.directory('/dest'),
    ])..home = '/home';

    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/dest')),
    );

    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var step = 0; step < 6; step++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  /// Копирует строку в соседнюю панель — как это делает человек.
  Future<void> copy(WidgetTester tester, String name) async {
    runtime.app.left.setCursorToName(name);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
  }

  Future<void> showHistory(WidgetTester tester) async {
    await runtime.commands.runAndWait(ShowHistoryCommand.commandId);
    await tester.pumpAndSettle();
  }

  List<String> rowsOf(WidgetTester tester) => [
    for (final row in tester.widget<FcPickList>(find.byType(FcPickList)).rows) row.title,
  ];

  testWidgets('работы показаны списком, новые первыми', (tester) async {
    await open(tester);
    await copy(tester, 'notes.txt');
    await copy(tester, 'report.txt');

    await showHistory(tester);

    expect(rowsOf(tester).length, 2);
    expect(find.textContaining('1 object'), findsWidgets, reason: 'сколько объектов задето — по журналу');
  });

  testWidgets('у необратимой работы причина стоит в строке', (tester) async {
    await open(tester);
    runtime.app.left.setCursorToName('notes.txt');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);

    await showHistory(tester);

    expect(find.textContaining('deleted permanently'), findsOneWidget);
  });

  testWidgets('отменяется только верхняя запись, и об этом говорят', (tester) async {
    await open(tester);
    await copy(tester, 'notes.txt');
    await copy(tester, 'report.txt');

    await showHistory(tester);
    // Встаём на вторую сверху — стрелкой, как это делает человек, — и просим
    // отменить её.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.textContaining('Only the newest'), findsOneWidget);
    expect(await provider.resolvePath().run('/dest/notes.txt'), isNotNull, reason: 'ничего не отменилось');
  });
}
