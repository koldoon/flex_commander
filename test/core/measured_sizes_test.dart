import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

List<FakeEntry> _entries() => [
  FakeEntry.directory('/home'),
  FakeEntry.directory('/home/docs'),
  FakeEntry.directory('/home/docs/inner'),
  FakeEntry.directory('/home/doc2'),
  FakeEntry.directory('/home/bin'),
];

const DirectoryTotals _some = DirectoryTotals(bytes: 300, workBytes: 300, entries: 4);

/// Память посчитанного (`docs/spec/directory-sizes.md`, §12).
void main() {
  late InMemoryTreeProvider provider;
  late MeasuredSizes sizes;

  setUp(() {
    provider = InMemoryTreeProvider(_entries());
    sizes = MeasuredSizes();
    // Пределы — настоящие по смыслу, но маленькие по числу: вытеснение
    // проверяется на десятке записей, а не на четырёх тысячах.
    MeasuredSizes.limit = 8;
    MeasuredSizes.askedLimit = 3;
  });

  tearDown(() {
    MeasuredSizes.limit = 4096;
    MeasuredSizes.askedLimit = 1024;
  });

  /// Узел по пути: вложенность настоящая — на ней и проверяется поддерево.
  DirectoryNode dir(String path, {TreeProvider? from}) {
    final source = from ?? provider;
    var at = source.rootDirectory;
    for (final name in path.split('/').where((part) => part.isNotEmpty)) {
      at = DirectoryNode(provider: source, name: name, parent: at);
    }
    return at;
  }

  group('итоги', () {
    test('положенное отдаётся обратно', () {
      final docs = dir('/home/docs');
      sizes.remember(docs, _some);

      expect(sizes.take(docs), _some);
    });

    test('чужому провайдеру не отдаётся', () {
      // Одинаковые пути у двух подключений к одному хосту — разные каталоги, и
      // различает их провайдер, а не строка.
      sizes.remember(dir('/home/docs'), _some);

      expect(sizes.take(dir('/home/docs', from: InMemoryTreeProvider(_entries()))), isNull);
    });

    test('предел вытесняет самое давнее', () {
      for (var i = 0; i < MeasuredSizes.limit + 2; i++) {
        sizes.remember(DirectoryNode(provider: provider, name: 'd$i', parent: provider.rootDirectory), _some);
      }

      expect(sizes.length, MeasuredSizes.limit);
      expect(sizes.take(DirectoryNode(provider: provider, name: 'd0', parent: provider.rootDirectory)), isNull);
    });

    test('попутное не теснит просьбу', () {
      // Человек попросил посчитать один каталог и число увидел.
      final asked = dir('/home/docs');
      sizes.remember(asked, _some, asked: true);

      // А потом обход прошёл через целое дерево: подкаталогов у него больше,
      // чем память вообще помнит.
      for (var i = 0; i < MeasuredSizes.limit * 3; i++) {
        sizes.remember(DirectoryNode(provider: provider, name: 'd$i', parent: provider.rootDirectory), _some);
      }

      expect(sizes.take(asked), _some, reason: 'просьбу попутное не вытесняет — её человек видит в колонке');
      expect(sizes.length, lessThanOrEqualTo(MeasuredSizes.limit + MeasuredSizes.askedLimit));
    });

    test('просьбу попутным проходом не разжаловать', () {
      final asked = dir('/home/docs');
      sizes.remember(asked, _some, asked: true);
      // Соседний обход прошёл через тот же каталог по дороге.
      sizes.remember(asked, _some);

      for (var i = 0; i < MeasuredSizes.limit * 3; i++) {
        sizes.remember(DirectoryNode(provider: provider, name: 'd$i', parent: provider.rootDirectory), _some);
      }

      expect(sizes.take(asked), _some);
    });

    test('просьбы вытесняют друг друга своим пределом', () {
      for (var i = 0; i < MeasuredSizes.askedLimit + 2; i++) {
        sizes.remember(
          DirectoryNode(provider: provider, name: 'a$i', parent: provider.rootDirectory),
          _some,
          asked: true,
        );
      }

      expect(sizes.askedLength, MeasuredSizes.askedLimit);
      expect(sizes.take(DirectoryNode(provider: provider, name: 'a0', parent: provider.rootDirectory)), isNull);
    });
  });

  group('забывание', () {
    test('уносит каталог, поддерево и предков', () {
      // Предков сегодня не забывает никто: скопировали в подкаталог, а сумма
      // родителя осталась вчерашней.
      sizes.remember(dir('/home'), _some);
      sizes.remember(dir('/home/docs'), _some);
      sizes.remember(dir('/home/docs/inner'), _some);
      sizes.remember(dir('/home/doc2'), _some);

      sizes.forget('/home/docs');

      expect(sizes.take(dir('/home/docs')), isNull, reason: 'сам каталог');
      expect(sizes.take(dir('/home/docs/inner')), isNull, reason: 'поддерево');
      expect(sizes.take(dir('/home')), isNull, reason: 'предок');
      // Сосед с похожим именем не поддерево: сравнение идёт по звеньям пути, а
      // не по началу строки.
      expect(sizes.take(dir('/home/doc2')), _some, reason: 'сосед по имени');
    });

    test('без поддерева — так просит слежение', () {
      sizes.remember(dir('/home'), _some);
      sizes.remember(dir('/home/docs'), _some);
      sizes.remember(dir('/home/docs/inner'), _some);

      sizes.forget('/home/docs', withSubtree: false);

      expect(sizes.take(dir('/home/docs')), isNull);
      expect(sizes.take(dir('/home')), isNull, reason: 'предок устарел точно');
      expect(sizes.take(dir('/home/docs/inner')), _some, reason: 'про поддерево событие ничего не говорило');
    });

    test('закрытый источник уносит свои записи', () {
      final other = InMemoryTreeProvider(_entries());
      sizes.remember(dir('/home/docs'), _some);
      sizes.remember(dir('/home/docs', from: other), _some);

      sizes.forgetProvider(provider);

      expect(sizes.take(dir('/home/docs')), isNull);
      expect(sizes.take(dir('/home/docs', from: other)), _some);
    });

    test('о забытом память рассказывает', () {
      // Число живёт не только здесь: панель пишет его в свои строки, и та, что
      // стоит не в забытом каталоге, иначе рисовала бы вчерашнее.
      final told = <String>[];
      sizes.onForgotten(told.addAll);
      sizes.remember(dir('/home/docs'), _some);

      sizes.forget('/home/docs');

      expect(told, contains('/home/docs'));
    });
  });

  group('идущий обход', () {
    MeasuredWalk walkThat(void Function() cancel) => MeasuredWalk(cancel: cancel);

    test('второй спрашивающий присоединяется, а не заводит свой', () async {
      final docs = dir('/home/docs');
      var started = 0;
      MeasuredWalk start() {
        started++;
        return walkThat(() {});
      }

      final first = sizes.claim(docs, start);
      final second = sizes.claim(docs, start);
      sizes.remember(docs, _some);

      expect(started, 1, reason: 'дерево обошли бы дважды');
      expect(await first, _some);
      expect(await second, _some);
    });

    test('обход живёт, пока нужен хоть кому-то', () {
      final docs = dir('/home/docs');
      var cancelled = false;
      final walk = sizes.announce(docs, () => walkThat(() => cancelled = true));
      sizes.claim(docs, () => fail('обход уже идёт'));

      // Человек снял пометку: его интерес ушёл, но обхода ждёт работа.
      sizes.drop(docs, walk);
      expect(cancelled, isFalse);
    });

    test('последний интерес гасит свет', () async {
      final docs = dir('/home/docs');
      var cancelled = false;
      final walk = sizes.announce(docs, () => walkThat(() => cancelled = true));

      sizes.drop(docs, walk);

      expect(cancelled, isTrue);
      expect(await walk.done, isNull, reason: 'ждущим — «считай сам»');
    });

    test('оборванный обход в память не попадает', () async {
      final docs = dir('/home/docs');
      final waiting = sizes.claim(docs, () => walkThat(() {}));

      sizes.abandon(docs);

      expect(await waiting, isNull);
      expect(sizes.take(docs), isNull);
    });
  });

  group('предки пути', () {
    test('обычный путь', () {
      expect(ancestorsOf('/home/docs/inner'), containsAllInOrder(['/home/docs', '/home', '/']));
    });

    test('внутри архива предком оказывается сам архив', () {
      expect(
        ancestorsOf('/home/a.zip:zip:/inner/x'),
        containsAllInOrder(['/home/a.zip:zip:/inner', '/home/a.zip:zip:/', '/home/a.zip', '/home']),
      );
    });

    test('выше корня источника предков нет', () {
      final ancestors = ancestorsOf('ssh://koldoon@shark/etc/apache2').toList();

      expect(ancestors, contains('ssh://koldoon@shark/etc'));
      expect(ancestors.every((path) => path.startsWith('ssh:')), isTrue, reason: '«//koldoon» наружу не выедет');
    });

    test('сосед по имени не поддерево', () {
      expect(isUnder('/home/doc2', '/home/doc'), isFalse);
      expect(isUnder('/home/doc/inner', '/home/doc'), isTrue);
    });
  });
}
