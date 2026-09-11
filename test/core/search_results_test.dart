import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/core/search_results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_panels/fc_panels.dart';

/// Найденное как содержимое панели — то, ради чего этап и затевался.
///
/// И **деревом**, а не плоским списком: видно, где что нашлось
/// (`docs/spec/file-search.md`, §4).
void main() {
  late AppRuntime runtime;
  late InMemoryContentProvider provider;

  PanelSession panel() => runtime.app.leftSession;

  setUp(() async {
    // С содержимым: умения строки — это умения её источника, и проверять их
    // на источнике без байтов было бы не о чем.
    provider = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/home/docs/deep'),
      FakeEntry.file('/home/docs/notes.txt', size: 10),
      FakeEntry.file('/home/docs/skip.md', size: 15),
      FakeEntry.file('/home/docs/deep/plan.txt', size: 20),
      FakeEntry.file('/home/readme.txt', size: 30),
    ])..home = '/home';
    runtime = await testApp(provider: provider, modules: featureModules());
    await runtime.app.start();
  });

  Future<DirectoryNode> dirAt(String path) async => (await provider.resolvePath().run(path))! as DirectoryNode;

  /// Находки: узлы по путям, как их отдал бы обход.
  Future<List<FsNode>> nodesAt(List<String> paths) async {
    final result = <FsNode>[];
    for (final path in paths) {
      final dir = await dirAt(path.substring(0, path.lastIndexOf('/')));
      final children = await provider.listChildren(dir);
      result.add(children.firstWhere((node) => node.pathString == path));
    }
    return result;
  }

  Future<SearchResultsProvider> results({String? under = '/home', List<String> found = const []}) async =>
      SearchResultsProvider(
        title: '*.txt',
        found: await nodesAt(found),
        parent: under == null ? null : await dirAt(under),
      );

  List<String> namesIn(DirectoryNode dir) => [for (final node in dir.nodes) node.name];

  test('находки ложатся по своим каталогам, а не в одну кучу', () async {
    final search = await results(found: ['/home/readme.txt', '/home/docs/notes.txt', '/home/docs/deep/plan.txt']);

    // Прямо в каталоге поиска — в корне; остальное под своими ветвями.
    expect(namesIn(search.rootDirectory), ['readme.txt', 'docs']);
    final docs = search.rootDirectory.nodes.whereType<DirectoryNode>().first;
    expect(namesIn(docs), ['notes.txt', 'deep']);
    expect(namesIn(docs.nodes.whereType<DirectoryNode>().first), ['plan.txt']);
  });

  test('ветвь виртуальная: в ней только найденное', () async {
    final search = await results(found: ['/home/docs/notes.txt']);
    final docs = search.rootDirectory.nodes.whereType<DirectoryNode>().first;

    // Настоящий `/home/docs` отдал бы и `skip.md`, и `deep` — находки утонули
    // бы среди соседей.
    expect(await search.listChildren(docs), hasLength(1));
    expect(namesIn(docs), ['notes.txt']);
    expect(docs.provider, same(search), reason: 'ветвь принадлежит находкам');
  });

  test('находки остаются настоящими узлами своих источников', () async {
    final search = await results(found: ['/home/docs/notes.txt']);
    final docs = search.rootDirectory.nodes.whereType<DirectoryNode>().first;
    final notes = docs.nodes.first;

    // На этом держится всё остальное: копирование, удаление и просмотр
    // спрашивают узел, а не панель.
    expect(notes.provider, same(provider));
    expect(notes.pathString, '/home/docs/notes.txt');
  });

  test('у ветви свой адрес, у находки — настоящий', () async {
    final search = await results(found: ['/home/docs/notes.txt']);
    final docs = search.rootDirectory.nodes.whereType<DirectoryNode>().first;

    // Пути должны различаться: по ним живут строки, пометка и раскрытое.
    expect(search.pathOf(search.rootDirectory), '/*.txt');
    expect(search.pathOf(docs), '/*.txt/docs');
    expect(docs.pathString, startsWith('/home:${SourceInfo.foundScheme}:/*.txt/docs'));
    expect(search.pathOf(docs.nodes.first), '/home/docs/notes.txt');
  });

  test('раскрыть надо все ветви: иначе находки спрятаны', () async {
    final search = await results(found: ['/home/docs/deep/plan.txt']);
    final docs = search.rootDirectory.nodes.whereType<DirectoryNode>().first;
    final deep = docs.nodes.whereType<DirectoryNode>().first;

    expect(search.openBranches, containsAll([search.rootDirectory.pathString, docs.pathString, deep.pathString]));
  });

  test('находка не из-под каталога поиска ложится в корень', () async {
    // Так приходит найденное по ссылке, уводящей в сторону: тянуть за собой
    // цепочку до самого диска незачем.
    final search = SearchResultsProvider(title: '*.txt', found: await nodesAt(['/home/docs/notes.txt']));

    expect(namesIn(search.rootDirectory), ['notes.txt']);
  });

  test('найденное становится списком панели, а прежний каталог помнится', () async {
    final search = await results(found: ['/home/docs/notes.txt', '/home/readme.txt']);

    await panel().open(search.rootDirectory);

    // Панель берёт провайдера у узла, которым её открыли, — отдельного «покажи
    // вот этот источник» заводить не пришлось.
    expect(panel().provider, same(search));
    expect(panel().entries.map((node) => node.name), containsAll(['readme.txt', 'docs']));
    expect(panel().entries.map((node) => node.name), contains('..'), reason: '`..` возвращает туда, где стояли');
  });

  test('находки открываются деревом, раскрытым до каждой', () async {
    final search = await results(found: ['/home/docs/deep/plan.txt', '/home/readme.txt']);
    expect(panel().view, PanelSettings.defaultView, reason: 'стенд ни о чём, если панель и так дерево');

    await panel().open(search.rootDirectory);
    await panel().setRows(RowsKind.tree);

    // Вид просит источник: плоским списком дерева находок не показать.
    expect(panel().view, 'tree');
    expect(
      [for (final entry in panel().entries) '${'  ' * entry.level}${entry.name}'],
      ['*.txt', '  docs', '    deep', '      plan.txt', '  readme.txt'],
    );
  });

  test('вид и раскрытое источника — не выбор человека', () async {
    final search = await results(found: ['/home/docs/notes.txt']);
    final was = panel().settings;

    await panel().open(search.rootDirectory);
    await panel().setRows(RowsKind.tree);
    // Человек волен посмотреть находки и таблицей — своей настройки он этим не
    // меняет.
    panel().setView(PanelSettings.defaultView);
    expect(panel().view, PanelSettings.defaultView);
    expect(panel().settings.view, was.view);
    expect(panel().settings.expanded, was.expanded, reason: '`found:`-пути в настройках панели не живут');

    // Ушли из находок — вернулся вид человека, и просьба источника его не
    // пережила.
    await panel().goUp();
    expect(panel().view, was.view);
  });

  test('находки идут в порядке обхода, а не по алфавиту', () async {
    // Список растёт по ходу поиска: всякая сортировка вставляла бы новое в
    // середину, и уже прочитанное на экране переезжало бы с каждой пачкой.
    final search = await results(found: ['/home/readme.txt', '/home/docs/notes.txt']);
    await panel().open(search.rootDirectory);

    expect(panel().entries.map((entry) => entry.name), ['..', 'readme.txt', 'docs']);

    // Щелчок по заголовку человек делает сам — тогда и раскладываем.
    panel().sortTo(const SortSpec());
    expect(panel().entries.map((entry) => entry.name), ['..', 'docs', 'readme.txt']);

    // Своей настройки он этим не менял: ушёл из находок — она прежняя.
    expect(panel().settings.sort.column, FsColumns.name);
    await panel().goUp();
    expect(panel().sort.column, FsColumns.name);
  });

  test('умения — у строки, а не у списка', () async {
    final search = await results(found: ['/home/docs/notes.txt']);
    await panel().open(search.rootDirectory);

    final branch = panel().entries.firstWhere((entry) => entry.name == 'docs');
    await panel().open(search.rootDirectory.nodes.whereType<DirectoryNode>().first);
    final note = panel().entries.firstWhere((entry) => entry.name == 'notes.txt');

    // Находка — настоящий узел своего источника: и отдать её содержимое, и
    // принять он умеет, поэтому `F4` над ней работает.
    expect(note.canStream, isTrue);
    expect(note.canReceive, isTrue);

    // А ветвь — своя, виртуальная: байтов у неё нет вовсе.
    expect(branch.canStream, isFalse);
    expect(branch.canReceive, isFalse);
  });

  test('в списке находок нечего писать', () async {
    final search = await results();

    expect(search.capabilities.realFileSystem, isFalse);
    expect(search is NodeEditor, isFalse, reason: 'править нечего: узлы принадлежат чужим источникам');
  });
}
