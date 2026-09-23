import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Источник находок: адреса строк, выход наверх и плоский список
/// (`docs/spec/file-search.md`, §4).
void main() {
  late InMemoryTreeProvider disk;

  setUp(() {
    disk = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/readme.txt', size: 10),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/notes.txt', size: 10),
      FakeEntry.directory('/home/docs/deep'),
      FakeEntry.file('/home/docs/deep/plan.txt', size: 20),
    ])..home = '/home';
  });

  Future<List<FsNode>> nodesAt(List<String> paths) async {
    final result = <FsNode>[];
    for (final path in paths) {
      final dir = await disk.resolvePath().run(path.substring(0, path.lastIndexOf('/'))) as DirectoryNode;
      final children = await disk.listChildren(dir);
      result.add(children.firstWhere((node) => node.pathString == path));
    }
    return result;
  }

  Future<SearchProvider> found(List<String> paths, {String content = 'TODO', String mask = ''}) async {
    final address = SearchAddress(where: '/home', query: SearchQuery(mask: mask, content: content));
    final source = SearchProvider(address, title: 'Find ${address.what}');
    source.add(await nodesAt(paths));
    return source;
  }

  test('адрес запроса живёт в пути строк', () async {
    final source = await found(['/home/docs/deep/plan.txt']);

    // Корень зовётся адресом, ветвь — местом внутри него: по строке источник
    // восстанавливается после перезапуска, как сервер по `ssh://…`.
    expect(source.rootDirectory.pathString, 'search:/?in=%2Fhome&content=TODO');
    final branch = source.rootDirectory.nodes.whereType<DirectoryNode>().single;
    expect(branch.pathString, 'search:/?in=%2Fhome&content=TODO#/docs');
    expect(branch.pathString, isNot(contains('//')), reason: 'звеньев чужого пути в адресе нет');
  });

  test('имя списка в пути не участвует', () async {
    // Прежде имя было звеном пути, и пустая маска ломала адреса всех строк.
    final address = SearchAddress(where: '/home', query: const SearchQuery(mask: '', content: 'TODO'));
    final source = SearchProvider(address, title: '');

    expect(source.rootDirectory.pathString, 'search:/?in=%2Fhome&content=TODO');
    expect(source.rootDirectory.pathString, isNot(contains('//')));
  });

  test('разбор пути не выдумывает', () async {
    final source = await found(['/home/docs/notes.txt']);
    final branch = source.rootDirectory.nodes.whereType<DirectoryNode>().single;

    expect(await source.resolvePath().run(source.rootDirectory.pathString), same(source.rootDirectory));
    expect(await source.resolvePath().run(branch.pathString), same(branch));
    // Промах — это «нет такого», а не «вот вам корень»: молчаливая подмена
    // уводила панель в начало списка на любую устаревшую ветвь.
    expect(await source.resolvePath().run('search:/?in=%2Fhome&content=TODO#/gone'), isNull);
  });

  test('раскрытое — это адреса строк', () async {
    final source = await found(['/home/docs/deep/plan.txt']);

    final rows = <String>[source.rootDirectory.pathString];
    void walk(DirectoryNode dir) {
      for (final node in dir.nodes.whereType<DirectoryNode>()) {
        if (identical(node.provider, source)) {
          rows.add(node.pathString);
          walk(node);
        }
      }
    }

    walk(source.rootDirectory);
    expect(source.openBranches, rows, reason: 'панель сравнивает их со своим раскрытым');
  });

  test('список — уровень, как у всякого каталога', () async {
    final source = await found(['/home/readme.txt', '/home/docs/notes.txt', '/home/docs/deep/plan.txt']);

    final listing = await source.getDirectoryListing().run(ListingParams(source.rootDirectory));

    // Ветви каталогами, находки файлами: в ветвь входят, а не разворачивают её
    // в общую кучу (`docs/spec/file-search.md`, §4а, Н3).
    expect(listing.map((node) => node.name), ['readme.txt', 'docs']);

    final branch = listing.whereType<DirectoryNode>().firstWhere((node) => node.name == 'docs');
    final inside = await source.getDirectoryListing().run(ListingParams(branch));
    expect(inside.map((node) => node.name), ['..', 'notes.txt', 'deep']);
  });

  test('всё найденное можно спросить и одной кучей', () async {
    // Списком панели это не служит, но нужно тому, кто считает находки.
    final source = await found(['/home/readme.txt', '/home/docs/notes.txt', '/home/docs/deep/plan.txt']);

    expect(source.flatUnder(source.rootDirectory).map((node) => node.name), ['readme.txt', 'notes.txt', 'plan.txt']);
  });

  test('в корне проекции «..» нет', () async {
    // Вверх из неё идти некуда: выйти из отобранного можно только явно —
    // сменой вкладки или переходом по адресу (§4.6). Иначе из списка
    // вываливались случайно, одним лишним нажатием.
    final source = await found(['/home/docs/notes.txt']);

    final listing = await source.getDirectoryListing().run(ListingParams(source.rootDirectory));
    expect(listing.map((node) => node.name), isNot(contains('..')));

    // А внутри проекции «..» на месте: там наверх есть куда.
    final branch = listing.whereType<DirectoryNode>().single;
    final inside = await source.getDirectoryListing().run(ListingParams(branch));
    expect(inside.map((node) => node.name), contains('..'));
  });

  test('находки остаются настоящими узлами своих источников', () async {
    final source = await found(['/home/docs/notes.txt']);

    final note = source.flatUnder(source.rootDirectory).single;
    expect(note.provider, same(disk), reason: 'копирование и правка работают без единой правки');
    expect(note.pathString, '/home/docs/notes.txt');
  });

  test('за каждым местом проекции стоит настоящий каталог', () async {
    final source = await found(['/home/docs/notes.txt']);
    final branch = source.rootDirectory.nodes.whereType<DirectoryNode>().single;

    expect(source.realPathOf(branch), '/home/docs');
    // За корнем стоит каталог, в котором искали: проекция начинается с него.
    expect(source.realPathOf(source.rootDirectory), '/home');
  });

  test('источник называет работу, которой наполняется', () async {
    final source = await found(['/home/readme.txt'], content: 'TODO', mask: '*.txt');

    final work = source.work;
    expect(work.kind, SearchWork.kind);
    expect(
      (work.destination as PathDestination).path,
      source.address.toString(),
      reason: 'находки складываются прямо в него',
    );
    expect(work.options[SearchWork.maskOption], '*.txt');
    expect(work.options[SearchWork.contentOption], 'TODO');
  });

  test('находка не из-под каталога поиска ложится в корень', () async {
    disk.add(FakeEntry.directory('/elsewhere'));
    disk.add(FakeEntry.file('/elsewhere/stray.txt', size: 1));
    final source = await found(['/elsewhere/stray.txt']);

    expect(source.rootDirectory.nodes.map((node) => node.name), ['stray.txt']);
  });
}
