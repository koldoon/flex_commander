import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Путь звеньями.
///
/// Спецификация — `docs/spec/panel-crumbs.md`.
void main() {
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/documents'),
    FakeEntry.directory('/home/documents/projects'),
    FakeEntry.directory('/home/documents/projects/commander'),
    FakeEntry.file('/home/documents/projects/commander/notes.txt', size: 10),
  ])..home = '/home';

  Future<AppRuntime> open(
    WidgetTester tester, {
    String path = '/home/documents/projects/commander',
    String header = crumbsHeaderId,
    Size size = const Size(2000, 700),
  }) async {
    final settings = AppSettings(left: PanelSettings(path: path), right: PanelSettings.defaults('/home'))
      ..panelHeader = header;
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settings);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Звено в заголовке левой панели.
  Finder crumb(String label) =>
      find.descendant(of: find.byType(CrumbsHeader).first, matching: find.text(label, findRichText: true));

  testWidgets('адрес показан звеньями', (tester) async {
    await open(tester);

    expect(crumb('/'), findsOneWidget);
    expect(crumb('home'), findsOneWidget);
    expect(crumb('documents'), findsOneWidget);
    expect(crumb('commander'), findsOneWidget);
    expect(find.byType(FcPathText), findsNothing, reason: 'строкой путь больше не набран');
  });

  testWidgets('последнее звено ярче остальных', (tester) async {
    final runtime = await open(tester);
    final theme = runtime.app.theme.current;

    // Через `RichText`: `find.text(findRichText: true)` находит именно его, а
    // цвет лежит в корневом отрезке.
    Color? colorOf(String label) => (tester.widget<RichText>(crumb(label)).text as TextSpan).style?.color;

    expect(colorOf('commander'), isNot(theme.colors.secondaryText));
    expect(colorOf('documents'), theme.colors.secondaryText);
    expect(colorOf('home'), theme.colors.secondaryText);
  });

  testWidgets('нажатие на звено уводит панель туда, и это шаг истории', (tester) async {
    final runtime = await open(tester);

    await tester.tap(crumb('documents'));
    await tester.pumpAndSettle();

    expect(runtime.app.left.currentPath, '/home/documents');

    // Обычный переход, а не особый случай: «назад» возвращает (§5).
    runtime.commands.dispatch(KeyCombination.parse('Cmd-['));
    await tester.pumpAndSettle();

    expect(runtime.app.left.currentPath, '/home/documents/projects/commander');
  });

  testWidgets('в узкой панели середина свёрнута, края на месте', (tester) async {
    await open(tester, size: const Size(560, 700));

    expect(crumb(CrumbsHeader.ellipsis), findsOneWidget);
    expect(crumb('/'), findsOneWidget, reason: 'первое звено говорит, где мы вообще');
    expect(crumb('commander'), findsOneWidget, reason: 'последнее — где именно');
    expect(crumb('documents'), findsNothing);
  });

  testWidgets('вид адреса выбирают в настройках', (tester) async {
    final runtime = await open(tester, header: '', size: const Size(1000, 1400));

    // Список собран из реестра: заголовок приносит модуль (§6).
    runtime.commands.dispatch(KeyCombination.parse('F9'));
    await tester.pumpAndSettle();
    expect(find.text('Panel address', findRichText: true), findsOneWidget);

    final chooser = find.byWidgetPredicate((w) => w is FcSelect<String> && w.options.containsKey(crumbsHeaderId));
    expect(chooser, findsOneWidget, reason: 'звенья предложены');

    tester.widget<FcSelect<String>>(chooser).onChanged!(crumbsHeaderId);
    await tester.pumpAndSettle();

    expect(runtime.app.panelHeader, crumbsHeaderId);
    expect(find.byType(CrumbsHeader), findsWidgets, reason: 'панели перерисовались на ходу');
  });

  testWidgets('не адрес показывается строкой', (tester) async {
    // Подпись, выставленная командой, звеньями не делится (§2).
    final runtime = await open(tester);
    runtime.app.left.setHeaderText('найдено 12');
    await tester.pumpAndSettle();

    expect(find.byType(FcPathText), findsWidgets);
  });
}
