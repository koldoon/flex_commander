import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/session_commands.dart';
import 'package:flex_commander/view/panel_row.dart';
import 'package:flex_commander/view/window_title_bar.dart';
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
    testWidgets('виден всегда — даже когда показаны оба набора', (tester) async {
      await pumpApp(tester);

      expect(app.panels.length, 2);
      // Ряд живёт в полосе заголовка и места ни у кого не отнимает.
      expect(find.descendant(of: find.byType(WindowTitleBar), matching: find.byType(PanelRow)), findsOneWidget);
      expect(find.descendant(of: find.byType(PanelRow), matching: find.text('home')), findsWidgets);
      expect(find.byKey(PanelRow.newPanelKey), findsOneWidget, reason: 'кнопка нового набора — последней');
    });

    testWidgets('непоказанный набор перечисляется в ряду', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.keyT, modifiers: [commandKey, LogicalKeyboardKey.shift]);

      expect(app.panels.length, 3, reason: 'Cmd-Shift-T заводит набор');
      // Три записи: показанные слева и справа и тот, кому места не досталось.
      expect(find.descendant(of: find.byType(PanelRow), matching: find.text('home')), findsWidgets);
    });

    testWidgets('записи не залезают на светофор и на ручку окна', (tester) async {
      // Окно тесное, наборов много: записям некуда деваться, кроме как ужаться.
      for (var more = 0; more < 4; more++) {
        await app.openPanel(ViewportPosition.left);
      }
      await pumpApp(tester);

      const metrics = DefaultMetrics();
      final free = metrics.windowControlsWidth + metrics.windowDragHandleWidth;
      final row = find.byType(PanelRow);
      expect(tester.getTopLeft(row).dx, greaterThanOrEqualTo(free));
    });

    testWidgets('ряд стоит по центру полосы и кончается там же, где панели', (tester) async {
      await pumpApp(tester);

      const metrics = DefaultMetrics();
      final bar = tester.getRect(find.byType(WindowTitleBar));
      final plus = tester.getRect(find.byKey(PanelRow.newPanelKey));
      final chip = tester.getRect(find.byKey(PanelRow.chipKey(1)));

      expect(plus.height, chip.height, reason: 'кнопка ростом с запись');
      expect(plus.top, chip.top, reason: 'и стоит с ней вровень');
      expect(
        chip.center.dy,
        bar.center.dy + metrics.windowTitleBarContentNudge,
        reason: 'по центру светофора — он ниже середины полосы',
      );
      expect(plus.right, bar.right - metrics.windowSidePadding, reason: 'поле окна одно на всё содержимое');
    });

    testWidgets('кнопка «плюс» заводит набор', (tester) async {
      await pumpApp(tester);
      final was = app.panels.length;

      // Без задержки: нажатие по записи не должно ждать срока двойного —
      // двойное живёт под рядом и достаётся пустым местам полосы.
      await tester.tap(find.byKey(PanelRow.newPanelKey));
      await tester.pumpAndSettle();

      expect(app.panels.length, was + 1);
      expect(app.left, same(app.panels[1].session), reason: 'заведённый показан здесь же');
    });

    testWidgets('метка горит у того, кто показан, и с той стороны', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.keyT, modifiers: [commandKey, LogicalKeyboardKey.shift]);

      // Показаны двое: заведённый слева и прежний правый. Значит, горящих
      // ячеек ровно по одной с каждой стороны — и в разных записях.
      expect(find.byKey(PanelRow.leftMarkKey), findsOneWidget);
      expect(find.byKey(PanelRow.rightMarkKey), findsOneWidget);

      // Один набор в обеих панелях — обе ячейки одной записи.
      app.showPanel(ViewportPosition.right, app.panelAt(ViewportPosition.left));
      await tester.pumpAndSettle();
      expect(find.byKey(PanelRow.leftMarkKey), findsOneWidget);
      expect(find.byKey(PanelRow.rightMarkKey), findsOneWidget);
      expect(app.left, same(app.right));
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

  group('один набор в обеих панелях', () {
    /// Плашки пути, горящие как активные: их должно быть не больше одной.
    Finder activePlates() => find.byWidgetPredicate((widget) => widget is FcPathPlate && widget.active);

    testWidgets('курсор всё равно один — там, где ввод', (tester) async {
      await pumpApp(tester);
      app.showPanel(ViewportPosition.right, app.panelAt(ViewportPosition.left));
      await tester.pumpAndSettle();

      expect(app.left, same(app.right), reason: 'сессия одна на две панели');
      expect(app.view.sourceArea, ViewportPosition.left);
      expect(activePlates(), findsOneWidget);
    });

    testWidgets('Tab уводит ввод на другую сторону той же сессии', (tester) async {
      await pumpApp(tester);
      app.showPanel(ViewportPosition.right, app.panelAt(ViewportPosition.left));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.tab);

      expect(app.view.sourceArea, ViewportPosition.right);
      expect(activePlates(), findsOneWidget);
    });

    testWidgets('щелчок по правой панели делает источником её', (tester) async {
      await pumpApp(tester);
      app.showPanel(ViewportPosition.right, app.panelAt(ViewportPosition.left));
      await tester.pumpAndSettle();

      // Половина окна вправо — там правая панель, чью бы сессию она ни
      // показывала.
      await tester.tapAt(const Offset(600, 300));
      await tester.pumpAndSettle();

      expect(app.view.sourceArea, ViewportPosition.right);
      expect(activePlates(), findsOneWidget);
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
