import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Найденное как содержимое панели — то, ради чего этап и затевался.
void main() {
  late AppRuntime runtime;
  late InMemoryTreeProvider provider;

  Panel panel() => runtime.app.left;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/notes.txt', size: 10),
      FakeEntry.file('/home/docs/plan.txt', size: 20),
      FakeEntry.file('/home/readme.md', size: 30),
    ])..home = '/home';
    runtime = await testApp(provider: provider, modules: featureModules());
    await runtime.app.start();
  });

  Future<List<FsNode>> nodesAt(String directory) async {
    final dir = await provider.resolvePath().run(directory) as DirectoryNode;
    return provider.listChildren(dir);
  }

  test('найденное становится списком панели, а прежний каталог помнится', () async {
    final found = await nodesAt('/home/docs');
    final results = SearchResultsProvider(title: '*.txt', found: found);

    await panel().open(results.rootDirectory);

    // Панель берёт провайдера у узла, которым её открыли, — отдельного «покажи
    // вот этот источник» заводить не пришлось.
    expect(panel().provider, same(results));
    expect(panel().nodes.map((node) => node.name), containsAll(['notes.txt', 'plan.txt']));
  });

  test('узлы настоящие: они принадлежат своему источнику', () async {
    final found = await nodesAt('/home/docs');
    final results = SearchResultsProvider(title: '*.txt', found: found);
    await panel().open(results.rootDirectory);

    final notes = panel().nodes.firstWhere((node) => node.name == 'notes.txt');

    // На этом держится всё остальное: копирование, удаление и просмотр
    // спрашивают узел, а не панель.
    expect(notes.provider, same(provider));
    expect(notes.pathString, contains('/home/docs/notes.txt'));
  });

  test('путь узла показывает, откуда он', () async {
    final found = await nodesAt('/home/docs');
    final results = SearchResultsProvider(title: '*.txt', found: found);

    final notes = found.firstWhere((node) => node.name == 'notes.txt');

    // В плоском списке одни имена бесполезны: `notes.txt` там будет десяток.
    expect(results.pathOf(notes), contains('/home/docs/notes.txt'));
  });

  test('в списке находок нечего писать', () async {
    final results = SearchResultsProvider(title: 'ничего', found: const []);

    expect(results.capabilities.realFileSystem, isFalse);
    expect(results is NodeEditor, isFalse, reason: 'править нечего: узлы принадлежат чужим источникам');
  });
}
