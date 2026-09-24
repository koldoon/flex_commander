import 'package:fc_api/fc_api.dart';

import 'search_limits.dart';
import 'search_query.dart';

/// Запрос поиска — адресом.
///
/// `search:/?in=/Users/koldoon&name=*.dart&content=TODO&words=1`
///
/// Адрес, а не набор полей, потому что из этого сразу следуют четыре вещи
/// (`docs/spec/file-search.md`, §4.1): искать можно помимо окна; состояние
/// панели восстановимо; одинаковый запрос — это один смонтированный источник;
/// а имя списка выводится из запроса и потому не бывает пустым.
///
/// Разбор и сборка живут **здесь и только здесь**: два места однажды разойдутся,
/// и разошлись бы молча — адрес читается машиной, а не человеком.
class SearchAddress {
  const SearchAddress({required this.where, required this.query, this.limits = const SearchLimits()});

  /// Схема источника находок — та же, которой он представляется панели.
  static const String scheme = SourceInfo.searchScheme;

  /// Где искать — каталог, от которого идёт обход.
  final String where;

  /// О чём спрашивают. Размер и дата сюда не входят: они живут в [limits]
  /// строками, как набраны.
  final SearchQuery query;

  /// Размер и дата — **как набраны**: `2M`, `7d`.
  ///
  /// Разобранное значение `7d` значит «семь дней назад от сейчас», и превратив
  /// его в дату при сборке адреса, мы заморозили бы вчерашний ответ на
  /// завтрашний вопрос (§10.5).
  final SearchLimits limits;

  /// Запрос вместе с разобранными пределами — тот, что уезжает работе.
  SearchQuery get fullQuery => query.copyWith(
    sizeFrom: () => limits.sizeFrom,
    sizeTo: () => limits.sizeTo,
    changedAfter: () => limits.changedAfter,
    changedBefore: () => limits.changedBefore,
  );

  /// Порядок полей закреплён: одинаковые запросы обязаны давать одинаковую
  /// строку, иначе «тот же поиск» перестанет быть тем же местом.
  Uri toUri() {
    final values = <String, String>{_where: where};

    void put(String key, String value) {
      // Умолчания в адрес не пишутся: иначе каждый адрес нёс бы полтора десятка
      // «нет», а два одинаковых запроса разошлись бы строкой.
      if (value.isNotEmpty) {
        values[key] = value;
      }
    }

    void flag(String key, bool value) => put(key, value ? '1' : '');

    put(_name, query.mask);
    flag(_regexp, query.regexp);
    flag(_case, query.caseSensitive);
    put(_ignore, query.ignore);
    flag(_links, query.followLinks);
    flag(_archives, query.archives);
    flag(_hidden, query.hidden);
    // Обратное умолчанию: обход по умолчанию рекурсивный, и «не заходить
    // внутрь» — это то, о чём стоит сказать.
    flag(_plain, !query.recursive);
    put(_content, query.content);
    flag(_contentRegexp, query.contentRegexp);
    flag(_contentCase, query.contentCase);
    flag(_words, query.wholeWords);
    flag(_charsets, query.allCharsets);
    put(_sizeFrom, limits.sizeFromText);
    put(_sizeTo, limits.sizeToText);
    put(_after, limits.afterText);
    put(_before, limits.beforeText);

    return Uri(scheme: scheme, path: '/', queryParameters: values);
  }

  @override
  String toString() => toUri().toString();

  /// Разобрать адрес; null — адрес не наш или в нём нет каталога.
  ///
  /// Не бросает: строка приходит извне — из настроек, из командной строки, — и
  /// негодная строка это ответ «не наше», а не беда.
  static SearchAddress? parse(String value) {
    final uri = Uri.tryParse(value);
    return uri == null ? null : of(uri);
  }

  static SearchAddress? of(Uri uri) {
    if (uri.scheme.toLowerCase() != scheme) {
      return null;
    }
    final values = uri.queryParameters;
    final where = values[_where] ?? '';
    if (where.isEmpty) {
      // Поиск без каталога — не поиск: обходить нечего.
      return null;
    }
    bool flag(String key) => values[key] == '1';
    return SearchAddress(
      where: where,
      query: SearchQuery(
        mask: values[_name] ?? '',
        regexp: flag(_regexp),
        caseSensitive: flag(_case),
        recursive: !flag(_plain),
        hidden: flag(_hidden),
        ignore: values[_ignore] ?? '',
        followLinks: flag(_links),
        archives: flag(_archives),
        content: values[_content] ?? '',
        contentRegexp: flag(_contentRegexp),
        contentCase: flag(_contentCase),
        wholeWords: flag(_words),
        allCharsets: flag(_charsets),
      ),
      limits: SearchLimits(
        sizeFromText: values[_sizeFrom] ?? '',
        sizeToText: values[_sizeTo] ?? '',
        afterText: values[_after] ?? '',
        beforeText: values[_before] ?? '',
      ),
    );
  }

  /// Чем этот поиск назвать человеку: искомое имя, иначе содержимое в кавычках.
  ///
  /// Пустым не бывает: запроса без имени и без содержимого не существует
  /// (`SearchQuery.isEmpty`), а `*` остаётся на случай, когда его всё-таки
  /// собрали руками.
  String get what {
    final mask = query.mask.trim();
    if (mask.isNotEmpty) {
      return mask;
    }
    final content = query.content.trim();
    return content.isEmpty ? '*' : '"$content"';
  }

  static const String _where = 'in';
  static const String _name = 'name';
  static const String _regexp = 'regexp';
  static const String _case = 'case';
  static const String _ignore = 'ignore';
  static const String _links = 'links';
  static const String _archives = 'archives';
  static const String _hidden = 'hidden';
  static const String _plain = 'plain';
  static const String _content = 'content';
  static const String _contentRegexp = 'contentRegexp';
  static const String _contentCase = 'contentCase';
  static const String _words = 'words';
  static const String _charsets = 'charsets';
  static const String _sizeFrom = 'sizeFrom';
  static const String _sizeTo = 'sizeTo';
  static const String _after = 'after';
  static const String _before = 'before';
}
