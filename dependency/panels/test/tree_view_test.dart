import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дерево каталогов.
///
/// Спецификация — `docs/spec/panel-view-tree.md`.
void main() {
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/lib'),
    FakeEntry.directory('/home/lib/src'),
    FakeEntry.directory('/home/test'),
    FakeEntry.directory('/home/.git'),
    FakeEntry.file('/home/main.dart', size: 1),
    FakeEntry.file('/home/lib/app.dart', size: 1),
    FakeEntry.file('/home/lib/src/panel.dart', size: 1),
    FakeEntry.file('/home/test/panel_test.dart', size: 1),
  ])..home = '/home';

  Future<AppRuntime> open(WidgetTester tester, {String at = '/home'}) async {
    final settings = AppSettings(left: PanelSettings.defaults(at), right: PanelSettings.defaults('/home'));
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settings);
    await runtime.app.start();

    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Что показывает плашка над панелью с деревом.
  String plate(WidgetTester tester) =>
      tester
          .widgetList<FcPathPlate>(
            find.descendant(of: find.byType(PanelView).first, matching: find.byType(FcPathPlate)),
          )
          .first
          .path;

  /// Помеченные ветви — по полосе пометки, которой строка и отличается на вид.
  int markedRows(WidgetTester tester) {
    final colors = FcTheme.of(tester.element(find.byType(TreeView))).colors;
    return tester
        .widgetList<ColoredBox>(find.descendant(of: find.byType(TreeView), matching: find.byType(ColoredBox)))
        .where((box) => box.color == colors.markedBar)
        .length;
  }

  /// Что видно в дереве, сверху вниз.
  List<String> branches(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(find.descendant(of: find.byType(TreeView), matching: find.byType(Text))))
      if ((text.data ?? '').isNotEmpty && (text.data ?? '').codeUnitAt(0) < 0xE000) text.data!,
  ];

  testWidgets('дерево открывается раскрытым до текущего каталога', (tester) async {
    await open(tester, at: '/home/lib');

    // Путь до текущего каталога развёрнут, а он сам раскрыт: видно и соседей,
    // и то, что внутри.
    expect(branches(tester), containsAllInOrder(['home', 'lib', 'src', 'app.dart']));
    expect(branches(tester), contains('test'));
  });

  testWidgets('строка дерева стоит по вертикали как строка списка', (tester) async {
    // Слева дерево, справа обычная таблица — и там и там есть `lib`. Панели
    // видны разом, и совпадать они обязаны до точки.
    final settings = AppSettings(
      left: PanelSettings(path: '/home', view: TreeView.viewId),
      right: PanelSettings.defaults('/home'),
    );
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settings);
    await runtime.app.start();
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    final names = find.text('lib');
    expect(names, findsNWidgets(2), reason: 'одно имя в дереве, другое в списке');

    double centreOfIcon(int i) =>
        tester
            .getRect(
              find.descendant(
                of: find.ancestor(of: names.at(i), matching: find.byType(Row)).first,
                matching: find.byType(FileTypeIcon),
              ),
            )
            .center
            .dy;

    expect(tester.getRect(names.at(0)).top, closeTo(tester.getRect(names.at(1)).top, 0.01));
    expect(centreOfIcon(0), closeTo(centreOfIcon(1), 0.01));
  });

  testWidgets('знак раскрытия только у каталогов', (tester) async {
    await open(tester);

    List<String> glyphsIn(String name) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
          matching: find.byType(Text),
        ),
      ))
        if ((text.data ?? '').isNotEmpty && text.data!.codeUnitAt(0) >= 0xE000) text.data!,
    ];

    final icons = FcTheme.of(tester.element(find.byType(TreeView))).icons;
    final closed = String.fromCharCode(icons.branchClosed.codePoint);

    expect(glyphsIn('lib'), contains(closed), reason: 'у каталога знак есть');
    expect(glyphsIn('main.dart'), isNot(contains(closed)), reason: 'у файла внутри ничего нет — и знака тоже');
  });

  testWidgets('знак ветви ложится на квадрат значка родителя', (tester) async {
    await open(tester, at: '/home/lib');

    // Значок объекта и знак раскрытия — один и тот же квадрат, а знак стоит
    // вплотную слева. Значит, шаг вглубь равен этому квадрату: у дочерней
    // ветви знак приходится ровно туда, где у родительской значок.
    Rect iconOf(String name) => tester.getRect(
      find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
        matching: find.byType(FileTypeIcon),
      ),
    );

    final metrics = FcTheme.of(tester.element(find.byType(TreeView))).metrics;
    final parent = iconOf('lib');
    final child = iconOf('src');

    // Знак дочерней ветви стоит сразу перед её значком, на ширину квадрата
    // с просветом: середина знака приходится на середину значка родителя.
    expect(
      child.left - parent.left,
      closeTo(parent.width + metrics.treeMarkGap, 0.01),
      reason: 'знак ребёнка встал на значок родителя',
    );
    expect(child.width, closeTo(parent.width, 0.01));
  });

  testWidgets('в дереве и каталоги, и файлы', (tester) async {
    await open(tester);

    expect(branches(tester), contains('lib'));
    expect(branches(tester), contains('main.dart'), reason: 'половина ответа «что где лежит» — это файлы');
  });

  testWidgets('стрелка водит курсор и больше ничего не трогает', (tester) async {
    final runtime = await open(tester);
    final before = branches(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();

    expect(branches(tester), before, reason: 'ветвь сама не раскрылась');
    expect(runtime.app.left.view, TreeView.viewId, reason: 'и вид остался деревом');
  });

  testWidgets('каталог панели идёт за курсором', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;
    expect(panel.path, '/home/lib');

    // Курсор на самой ветви `lib` — под ним `src`. Спускаемся, раскрываем и
    // уходим курсором внутрь.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();

    expect(panel.path, '/home/lib/src', reason: 'каталог панели — тот, в котором ветвь под курсором');
    expect(plate(tester), '/home/lib/src', reason: 'и плашка говорит о нём же');
    expect(panel.currentEntry?.name, 'panel.dart', reason: 'курсор панели — на том же объекте');
    expect(panel.busy, isFalse, reason: 'панель за это не платит занятостью');

    // И обратно: курсор вышел из ветви — панель вышла с ним.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();

    expect(panel.path, '/home/lib', reason: 'курсор вернулся на `src`, а тот лежит в `lib`');
  });

  testWidgets('на корне панель остаётся там, где стояла', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    runtime.commands.dispatch(KeyCombination.parse('Home'));
    await tester.pumpAndSettle();

    expect(branches(tester).first, '/', reason: 'курсор на корне источника');
    expect(panel.path, '/home/lib', reason: 'корень ни в каком каталоге не лежит');
  });

  testWidgets('Enter раскрывает ветвь и сворачивает обратно', (tester) async {
    final runtime = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    final before = branches(tester).length;

    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, greaterThan(before), reason: 'ветвь раскрылась');

    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, before, reason: 'и свернулась обратно');
  });

  testWidgets('Left на файле уводит в его каталог, а следующий — сворачивает', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Курсор на ветви `lib`; спускаемся на файл внутри неё.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.currentEntry?.name, 'app.dart');

    // Первый `Left` — к каталогу, в котором файл лежит.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();

    expect(panel.currentEntry?.name, 'lib', reason: 'курсор ушёл на саму ветвь');
    expect(panel.path, '/home', reason: 'а `lib` лежит в корне');
    expect(branches(tester), contains('app.dart'), reason: 'ветвь при этом не свернулась');

    // Второй — сворачивает её.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();

    expect(branches(tester), isNot(contains('app.dart')));
    expect(panel.currentEntry?.name, 'lib', reason: 'курсор остался на ней же');
  });

  testWidgets('Right и Left делают то же самое', (tester) async {
    final runtime = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    final before = branches(tester).length;

    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, greaterThan(before));

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, before);
  });

  testWidgets('Space помечает ветвь под курсором и шагает вниз', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Курсор на ветви `lib`; спускаемся на `src` и помечаем его.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    expect(panel.markedPaths, {'/home/lib/src'}, reason: 'помечена ветвь под курсором');
    expect(markedRows(tester), 1, reason: 'и это видно в дереве');

    // Обратно вверх и ещё раз — пометка снимается.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    expect(panel.markedPaths, isEmpty);
    expect(markedRows(tester), 0);
  });

  testWidgets('пометка из разных ветвей складывается', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Помечаем `src` в `lib` — курсор от пометки уходит на `app.dart`…
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    // …уходим курсором в соседнюю ветвь и помечаем там.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.path, '/home/test', reason: 'курсор ушёл в соседнюю ветвь');

    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    expect(panel.markedPaths, {'/home/lib/src', '/home/test/panel_test.dart'});
    expect(markedRows(tester), 2, reason: 'обе ветви показывают пометку');
  });

  testWidgets('скрытые каталоги приходят вместе с Cmd-H', (tester) async {
    final runtime = await open(tester);
    expect(branches(tester), isNot(contains('.git')));

    await runtime.app.left.setShowHidden(true);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(branches(tester), contains('.git'));
  });
}
