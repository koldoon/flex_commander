import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/session_commands.dart';
import 'package:flex_commander/view/panel_row.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ряд открытых наборов и команды сессий (`docs/spec/panel-sessions.md`).
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  // Платформа в widget-тестах не macOS, поэтому «командная» клавиша здесь —
  // Ctrl: ровно то, во что KeyCombination сворачивает Cmd вне macOS.
  const commandKey = LogicalKeyboardKey.control;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/work'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/work/report.txt', size: 20),
    ]);
    app =
        (await testApp(
          provider: provider,
          modules: featureModules(),
          settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/docs')),
        )).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
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

  group('ряд', () {
    testWidgets('пока показано всё, ряда нет', (tester) async {
      await pumpApp(tester);

      expect(app.panels.length, 2);
      expect(find.byType(PanelRow), findsOneWidget);
      // Виджет в дереве есть всегда, а строки не занимает: показывать нечего.
      expect(tester.getSize(find.byType(PanelRow)).height, 0);
    });

    testWidgets('непоказанный набор поднимает ряд и перечисляется в нём', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.keyT, modifiers: [commandKey, LogicalKeyboardKey.shift]);

      expect(app.panels.length, 3, reason: 'Cmd-Shift-T заводит набор');
      expect(tester.getSize(find.byType(PanelRow)).height, greaterThan(0));
      // Три записи: показанные слева и справа и тот, кому места не досталось.
      expect(find.descendant(of: find.byType(PanelRow), matching: find.text('home')), findsWidgets);
    });

    testWidgets('нажатие по записи показывает набор в активной панели', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.keyT, modifiers: [commandKey, LogicalKeyboardKey.shift]);
      await app.left.openPath('/work');
      await tester.pumpAndSettle();

      final hidden = app.panels.firstWhere(
        (panel) =>
            !identical(panel, app.panelAt(ViewportPosition.left)) &&
            !identical(panel, app.panelAt(ViewportPosition.right)),
      );
      await tester.tap(find.descendant(of: find.byType(PanelRow), matching: find.text(panelTitle(hidden, app.panels))));
      await tester.pumpAndSettle();

      expect(app.panelAt(ViewportPosition.left), same(hidden), reason: 'курсор стоял слева');
    });
  });

  group('команды', () {
    testWidgets('Cmd-Shift-T заводит набор здесь же и на том же каталоге', (tester) async {
      await pumpApp(tester);
      await app.left.openPath('/work');
      await tester.pumpAndSettle();
      final was = app.left;

      await press(tester, LogicalKeyboardKey.keyT, modifiers: [commandKey, LogicalKeyboardKey.shift]);

      expect(app.left, isNot(same(was)), reason: 'показан заведённый');
      expect(app.left.currentPath, '/work');
      expect(was.currentPath, '/work', reason: 'прежний жив и стоит там же');
      expect(app.right.currentPath, '/home/docs', reason: 'соседняя сторона не тронута');
    });

    testWidgets('Ctrl-Tab показывает здесь соседний набор', (tester) async {
      await pumpApp(tester);
      final first = app.panelAt(ViewportPosition.left);

      await press(tester, LogicalKeyboardKey.tab, modifiers: [LogicalKeyboardKey.control]);

      expect(app.panelAt(ViewportPosition.left), same(app.panels[1]));
      expect(app.panelAt(ViewportPosition.left), isNot(same(first)));
      expect(
        app.panelAt(ViewportPosition.right),
        same(app.panels[1]),
        reason: 'один набор в обеих панелях — обычное дело',
      );
    });

    testWidgets('Alt-2 показывает здесь второй набор', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.digit2, modifiers: [LogicalKeyboardKey.alt]);

      expect(app.panelAt(ViewportPosition.left), same(app.panels[1]));
    });

    testWidgets('Cmd-Shift-W закрывает показанный здесь', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.keyT, modifiers: [commandKey, LogicalKeyboardKey.shift]);
      expect(app.panels.length, 3);

      await press(tester, LogicalKeyboardKey.keyW, modifiers: [commandKey, LogicalKeyboardKey.shift]);

      expect(app.panels.length, 2);
      expect(app.left.currentPath, '/home/docs', reason: 'показан следующий по списку');
    });

    testWidgets('имя даётся набору и переживает смену каталога', (tester) async {
      await pumpApp(tester);
      app.commands.run(
        RenameSessionCommand.commandId,
        const CommandInvocation(parameters: {RenameSessionCommand.nameParam: 'сборка'}),
      );
      await tester.pumpAndSettle();

      final panel = app.panelAt(ViewportPosition.left);
      expect(panel.name, 'сборка');

      await app.left.openPath('/work');
      await tester.pumpAndSettle();
      expect(panel.name, 'сборка');
      expect(panelTitle(panel, app.panels), 'сборка');
    });
  });
}
