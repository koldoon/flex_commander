import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обход дерева: что находится и когда об этом узнают.
void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/readme.md', size: 10),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/notes.txt', size: 10),
      FakeEntry.file('/home/docs/plan.txt', size: 10),
      FakeEntry.file('/home/docs/plan.txt.bak', size: 10),
      FakeEntry.directory('/home/docs/deep'),
      FakeEntry.file('/home/docs/deep/buried.txt', size: 10),
      FakeEntry.file('/home/.hidden.txt', size: 10),
    ])..home = '/home';
  });

  Future<DirectoryNode> home() async => await provider.resolvePath().run('/home') as DirectoryNode;

  Future<List<String>> search(SearchQuery query, {List<String>? asFound}) async {
    final run = SearchRun.from(await home(), onFound: (node) => asFound?.add(node.name));
    final found = await run.run(query);
    return found.map((node) => node.name).toList();
  }

  test('маска отбирает по всему дереву', () async {
    final names = await search(const SearchQuery(mask: '*.txt'));

    expect(names, containsAll(['notes.txt', 'plan.txt', 'buried.txt']));
    expect(names, isNot(contains('readme.md')));
  });

  test('исключение работает тем же движком, что и у пометки', () async {
    // `*.txt;!*.bak` — та же строка, что человек пишет в окне пометки.
    final names = await search(const SearchQuery(mask: '*.txt;!*.bak'));

    expect(names, contains('plan.txt'));
    expect(names, isNot(contains('plan.txt.bak')));
  });

  test('без вложенных — только этот каталог', () async {
    final names = await search(const SearchQuery(mask: '*.txt', recursive: false));

    expect(names, isNot(contains('notes.txt')));
    expect(names, isNot(contains('buried.txt')));
  });

  test('скрытые берутся, только когда попросят', () async {
    expect(await search(const SearchQuery(mask: '*.txt')), isNot(contains('.hidden.txt')));
    expect(await search(const SearchQuery(mask: '*.txt', hidden: true)), contains('.hidden.txt'));
  });

  test('пустая маска не находит ничего и дерево не обходит', () async {
    expect(await search(const SearchQuery(mask: '')), isEmpty);
    expect(await search(const SearchQuery(mask: '   ')), isEmpty);
  });

  test('каталог тоже подходит под маску — и всё равно обходится', () async {
    final names = await search(const SearchQuery(mask: 'd*'));

    expect(names, contains('docs'), reason: 'сам каталог подошёл');
    expect(names, contains('deep'), reason: 'и вложенный в него — значит, внутрь зашли');
  });

  test('найденное отдаётся по ходу, а не в конце', () async {
    // На большом дереве первые попадания должны быть видны сразу.
    final asFound = <String>[];
    final names = await search(const SearchQuery(mask: '*.txt'), asFound: asFound);

    expect(asFound, isNotEmpty);
    expect(asFound, names, reason: 'по ходу пришло то же и в том же порядке');
  });

  test('обход называет каталог, в котором он сейчас', () async {
    // То, что показывает строка хода работы: где идём. Как в `mc` — человек
    // видит, что работа не встала, и по каталогу понимает, куда её занесло.
    // Путь при этом человеческий: машинный несёт схемы провайдеров
    // (`…/a.zip:zip:/inner`), и читать их в этой строке незачем.
    final run = SearchRun.from(await home(), onFound: (_) {});
    final seen = <String>[];
    run.status.addListener(() {
      final at = run.status.message;
      if (at.isNotEmpty) {
        seen.add(at);
      }
    });

    run.start(const SearchQuery(mask: '*.txt'));
    await run.result;

    expect(seen, containsAll(<String>['/home', '/home/docs', '/home/docs/deep']));
  });

  test('обход отдаёт управление циклу событий, а не занимает его целиком', () async {
    // Это не про вежливость, а про то, работает ли приложение во время поиска.
    // Локальный провайдер читает каталог синхронно, а `await` над готовым —
    // микрозадача; микрозадачи выполняются **до** кадра. Без вдоха весь обход
    // укладывается в один оборот цикла: ни кадра, ни таймера, пока он не
    // кончится, и прервать его тоже нечем.
    //
    // Дерево здесь нарочно медленное: вдох делается по времени, и на мгновенных
    // каталогах его могло бы не случиться вовсе.
    final slow = _BlockingProvider([
      FakeEntry.directory('/home'),
      for (var i = 0; i < 40; i++) FakeEntry.directory('/home/dir$i'),
    ])..home = '/home';
    final root = (await slow.resolvePath().run('/home'))! as DirectoryNode;

    var breathed = false;
    var breathedDuringWork = false;

    final run = SearchRun.from(root, onFound: (_) {});
    // Обычный таймер, заведённый до начала обхода: если обход не отдаёт
    // управление, он не сработает до самого его конца.
    unawaited(Future<void>.delayed(Duration.zero, () => breathed = true));
    run.status.addListener(() {
      if (breathed) {
        breathedDuringWork = true;
      }
    });

    run.start(const SearchQuery(mask: '*.txt'));
    await run.result;

    expect(breathedDuringWork, isTrue, reason: 'таймер сработал по ходу обхода, а не после него');
  });

  test('каталог, в который не пустили, поиск не прекращает', () async {
    provider.denied['/home/docs'] = const FsError('/home/docs', FsErrorKind.permissionDenied);

    final names = await search(const SearchQuery(mask: '*.md'));

    expect(names, contains('readme.md'), reason: 'непрочитанный каталог посреди дерева — обычное дело');
  });
}

/// Дерево, которое читается **синхронно и небыстро** — как настоящий диск.
///
/// Ровно то, на чём приложение и вставало: `listChildren` локального провайдера
/// не ждёт ничего, а считает, и без вдоха обход не отдаёт поток никому.
class _BlockingProvider extends InMemoryTreeProvider {
  _BlockingProvider(super.entries);

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final busy = Stopwatch()..start();
    while (busy.elapsed < const Duration(milliseconds: 1)) {
      // Занято: именно занято, а не ждём.
    }
    return super.listChildren(dir);
  }
}
