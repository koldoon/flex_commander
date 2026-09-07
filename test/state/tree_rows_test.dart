import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Панель показывает дерево тем же способом, что и список: строками
/// (`docs/spec/panel-node-list.md`, §3).
void main() {
  late InMemoryTreeProvider provider;
  late TestPanel panel;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/lib'),
      FakeEntry.directory('/home/lib/src'),
      FakeEntry.file('/home/lib/app.dart', size: 20),
      FakeEntry.file('/home/main.dart', size: 100),
      FakeEntry.directory('/other'),
    ]);
    panel = testPanel(provider: provider, settings: PanelSettings.defaults('/home'));
    await panel.openPath('/home');
  });

  tearDown(() => panel.dispose());

  List<String> rows() => [for (final entry in panel.session.entries) '${'  ' * entry.level}${entry.name}'];

  void cursorTo(String name) => panel.setCursorToName(name);

  test('вид просит дерево — и получает строки с глубиной', () async {
    await panel.session.setRows(RowsKind.tree);

    // Корень источника, а под ним раскрытая цепочка до каталога панели:
    // иначе панель показала бы дерево, в котором её самой не видно.
    expect(rows(), ['/', '  home', '    lib', '    main.dart', '  other']);
  });

  test('в дереве курсор встаёт на ветвь своего каталога', () async {
    await panel.session.setRows(RowsKind.tree);

    // Иначе панель окажется на корне — в дереве длиной во весь диск.
    expect(panel.session.currentNode?.name, 'home');
  });

  test('обратно в список — каталог той ветви, где стоял курсор', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);
    cursorTo('app.dart');

    await panel.session.setRows(RowsKind.listing);

    // Стояли на `app.dart` в ветви `lib` — список показывает её каталог, а
    // курсор остаётся на том же объекте.
    expect(panel.session.currentPath, '/home/lib');
    expect(rows(), ['..', 'src', 'app.dart']);
    expect(panel.session.currentNode?.name, 'app.dart');
  });

  test('корень каталогом панели не бывает', () async {
    await panel.session.setRows(RowsKind.tree);
    final wasAt = panel.session.currentPath;

    cursorTo('/');

    // Корень ни в чём не лежит: курсор на нём оставляет панель там, где она
    // стояла (`docs/spec/panel-view-tree.md`, §3).
    expect(panel.session.currentPath, wasAt);
  });

  test('ветвь раскрывается и сворачивается по пути', () async {
    await panel.session.setRows(RowsKind.tree);

    await panel.session.setExpanded('/home/lib', expanded: true);
    expect(rows(), ['/', '  home', '    lib', '      src', '      app.dart', '    main.dart', '  other']);

    await panel.session.setExpanded('/home/lib', expanded: false);
    expect(rows(), ['/', '  home', '    lib', '    main.dart', '  other']);
  });

  test('строки знают свою раскрытость', () async {
    await panel.session.setRows(RowsKind.tree);

    final home = panel.session.entries.firstWhere((entry) => entry.name == 'home');
    final other = panel.session.entries.firstWhere((entry) => entry.name == 'other');
    expect(home.isOpen, isTrue);
    expect(other.isOpen, isFalse);
  });

  test('курсор держится за строку, а не за место', () async {
    await panel.session.setRows(RowsKind.tree);
    cursorTo('main.dart');

    await panel.session.setExpanded('/home/lib', expanded: true);

    // Строка уехала вниз — курсор остался на ней.
    expect(panel.session.currentNode?.name, 'main.dart');
  });

  test('каталог операции идёт за курсором и ничего не читает', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    cursorTo('app.dart');
    expect(panel.session.currentPath, '/home/lib');

    cursorTo('home');
    expect(panel.session.currentPath, '/');

    // Панель при этом не читала ни одного каталога: строки уже собраны, а
    // курсор — это курсор (`docs/spec/panel-view-tree.md`, §3).
    expect(panel.session.status, PanelPhase.idle);
    expect(panel.session.busy, isFalse);
  });

  test('пометка в дереве живёт путями и переживает раскрытие', () async {
    await panel.session.setRows(RowsKind.tree);
    cursorTo('main.dart');
    panel.session.toggleCurrentMark();

    await panel.session.setExpanded('/home/lib', expanded: true);

    expect(panel.session.selection.paths, {'/home/main.dart'});
  });

  test('сортировка раскладывает ветви, а не мешает их с содержимым', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    panel.session.sortTo(const SortSpec(direction: SortDirection.descending));

    // Порядок переворачивается **внутри** ветвей, а ветви со своим
    // содержимым не перемешиваются; каталоги остаются выше файлов.
    expect(rows(), ['/', '  other', '  home', '    lib', '      src', '      app.dart', '    main.dart']);
  });
}
