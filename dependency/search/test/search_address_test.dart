import 'package:fc_search/fc_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// Запрос адресом: по нему монтируется источник, им же восстанавливается
/// состояние панели (`docs/spec/file-search.md`, §4.1).
void main() {
  SearchAddress? back(SearchAddress address) => SearchAddress.parse(address.toString());

  test('адрес обратим', () {
    final address = SearchAddress(
      where: '/Users/koldoon',
      query: const SearchQuery(
        mask: '*.dart;!*.g.dart',
        regexp: false,
        caseSensitive: true,
        recursive: false,
        hidden: true,
        ignore: 'node_modules;.git',
        followLinks: true,
        content: 'TODO: разобраться',
        contentRegexp: false,
        contentCase: true,
        wholeWords: true,
        allCharsets: true,
      ),
      limits: const SearchLimits(sizeFromText: '1k', sizeToText: '2M', afterText: '7d', beforeText: '2026-09-01'),
    );

    final read = back(address)!;

    expect(read.toString(), address.toString(), reason: 'та же строка — тот же поиск');
    expect(read.where, '/Users/koldoon');
    expect(read.query.mask, '*.dart;!*.g.dart');
    expect(read.query.caseSensitive, isTrue);
    expect(read.query.recursive, isFalse);
    expect(read.query.hidden, isTrue);
    expect(read.query.ignore, 'node_modules;.git');
    expect(read.query.followLinks, isTrue);
    expect(read.query.content, 'TODO: разобраться');
    expect(read.query.contentCase, isTrue);
    expect(read.query.wholeWords, isTrue);
    expect(read.query.allCharsets, isTrue);
    expect(read.limits.sizeFromText, '1k');
    expect(read.limits.beforeText, '2026-09-01');
  });

  test('пустое имя при заданном содержимом переживает дорогу', () {
    // Тот самый запрос, на котором прежняя сборка ломала все адреса разом.
    final address = SearchAddress(where: '/home', query: const SearchQuery(mask: '', content: 'TODO'));

    final read = back(address)!;

    expect(read.query.mask, isEmpty);
    expect(read.query.content, 'TODO');
    expect(read.what, '"TODO"', reason: 'назвать список всё равно есть чем');
  });

  test('умолчания в адрес не пишутся', () {
    final address = SearchAddress(where: '/home', query: const SearchQuery(mask: '*.txt'));

    final uri = address.toUri();

    expect(uri.queryParameters.keys, ['in', 'name']);
    expect(uri.toString(), 'search:/?in=%2Fhome&name=%2A.txt');
  });

  test('двоеточие в запросе не разваливает путь', () {
    // Пути приложения разбираются по двоеточиям (`NodePath.parse`), поэтому
    // значения обязаны уезжать закодированными — иначе `TODO:` откусит хвост
    // адреса и притворится схемой.
    final address = SearchAddress(where: '/home', query: const SearchQuery(mask: '', content: 'a:b'));

    expect(address.toString(), isNot(contains('a:b')));
    expect(back(address)!.query.content, 'a:b');
  });

  test('чужой или негодный адрес — не наш, и это не беда', () {
    expect(SearchAddress.parse('/Users/koldoon'), isNull);
    expect(SearchAddress.parse('ssh://host/etc'), isNull);
    expect(SearchAddress.parse('search:/?name=*.dart'), isNull, reason: 'искать негде');
    expect(SearchAddress.parse('::::'), isNull);
  });

  test('пределы едут строками, а разбираются по требованию', () {
    final address = SearchAddress(
      where: '/home',
      query: const SearchQuery(mask: '*'),
      limits: const SearchLimits(sizeFromText: '1k'),
    );

    // В адресе — то, что набрал человек; разобранное берётся у запроса, и
    // относительная дата остаётся относительной.
    expect(address.toUri().queryParameters['sizeFrom'], '1k');
    expect(address.fullQuery.sizeFrom, 1024);
  });

  test('имя списка берётся из запроса', () {
    expect(SearchAddress(where: '/home', query: const SearchQuery(mask: '*.dart')).what, '*.dart');
    expect(SearchAddress(where: '/home', query: const SearchQuery(mask: '', content: 'TODO')).what, '"TODO"');
    expect(SearchAddress(where: '/home', query: const SearchQuery(mask: '')).what, '*');
  });
}
