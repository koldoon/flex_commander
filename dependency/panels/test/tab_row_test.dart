import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вкладки панелей (`docs/spec/panel-tabs.md`).
void main() {
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/docs'),
    FakeEntry.directory('/home/lib'),
    FakeEntry.directory('/home/lib/src'),
    FakeEntry.directory('/work'),
    FakeEntry.directory('/work/src'),
    FakeEntry.file('/home/notes.txt', size: 3),
  ])..home = '/home';

  Future<AppRuntime> open(WidgetTester tester) async {
    final runtime = await testApp(
      provider: provider(),
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    return runtime;
  }

  List<PanelTab> tabs(AppRuntime runtime) => runtime.app.tabsAt(ViewportPosition.left);

  testWidgets('пока вкладка одна, ряда не видно', (tester) async {
    final runtime = await open(tester);

    expect(tabs(runtime).length, 1);
    expect(find.byType(PanelTabRow), findsWidgets, reason: 'место под ряд есть всегда');
    expect(find.text('home'), findsNothing, reason: 'а самого ряда — нет');
  });

  testWidgets('Cmd-Shift-T заводит вкладку рядом и показывает её', (tester) async {
    final runtime = await open(tester);
    final first = runtime.app.left;

    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-T'));
    await tester.pumpAndSettle();

    expect(tabs(runtime).length, 2);
    expect(runtime.app.left, isNot(same(first)), reason: 'заведённая и показывается');
    expect(runtime.app.left.currentPath, '/home', reason: 'на текущем каталоге');
    // Прежняя жива и стоит там же.
    expect(first.currentPath, '/home');
  });

  testWidgets('переключение туда и обратно ничего не перечитывает', (tester) async {
    final runtime = await open(tester);
    final first = runtime.app.left;

    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-T'));
    await tester.pumpAndSettle();
    await runtime.app.left.openPath('/work');
    await tester.pumpAndSettle();
    final second = runtime.app.left;

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-Tab'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, same(first), reason: 'по кругу — к первой');

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-Tab'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, same(second));
    expect(second.currentPath, '/work', reason: 'вкладка помнит свой каталог');
  });

  testWidgets('Alt-2 показывает вторую, а Cmd-Shift-W закрывает', (tester) async {
    final runtime = await open(tester);
    final first = runtime.app.left;

    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-T'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Alt-1'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, same(first));

    runtime.commands.dispatch(KeyCombination.parse('Alt-2'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, isNot(same(first)));

    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-W'));
    await tester.pumpAndSettle();
    expect(tabs(runtime).length, 1);
    expect(runtime.app.left, same(first), reason: 'осталась соседка');
  });

  testWidgets('последняя вкладка не закрывается', (tester) async {
    final runtime = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-W'));
    await tester.pumpAndSettle();

    expect(tabs(runtime).length, 1);
  });

  testWidgets('ряд показывает вкладки, а совпавшие имена разводит родителем', (tester) async {
    final runtime = await open(tester);
    await runtime.app.left.openPath('/home/lib/src');
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-T'));
    await tester.pumpAndSettle();
    await runtime.app.left.openPath('/work/src');
    await tester.pumpAndSettle();

    final row = find.byType(PanelTabRow);
    expect(find.descendant(of: row, matching: find.text('src — lib')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('src — work')), findsOneWidget);
  });

  testWidgets('уход из закреплённой открывает новую, а сама она остаётся', (tester) async {
    final runtime = await open(tester);
    final pinned = tabs(runtime).first;

    runtime.app.setTabPinned(pinned, true);
    await tester.pumpAndSettle();

    // Уходим из неё — как обычно, открытием каталога.
    await runtime.app.left.openPath('/work');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(tabs(runtime).length, 2, reason: 'новый каталог уехал в новую вкладку');
    expect(pinned.panel.currentPath, '/home', reason: 'а закреплённая осталась на своём');
    expect(runtime.app.left.currentPath, '/work', reason: 'и показывается новая');
  });

  testWidgets('щелчок по вкладке показывает её', (tester) async {
    final runtime = await open(tester);
    final first = runtime.app.left;
    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-T'));
    await tester.pumpAndSettle();
    await runtime.app.left.openPath('/work');
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(PanelTabRow), matching: find.text('home')));
    await tester.pumpAndSettle();

    expect(runtime.app.left, same(first));
  });
}
