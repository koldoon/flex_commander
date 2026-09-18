import 'package:fc_api/fc_api.dart';

import 'search_address.dart';

/// Как зовут работу поиска и её доводы.
///
/// Отдельным файлом, потому что имена нужны **обеим** сторонам: экран собирает
/// заявку, ядро по ней узнаёт свою работу. Здесь только строки — ни дерева, ни
/// провайдеров, — и потому этот файл видят обе половины модуля, не таща за
/// собой чужой половины (`docs/spec/client-server.md`, §8).
abstract final class SearchWork {
  /// Заявка на обход по адресу запроса.
  ///
  /// Одна сборка на обе стороны: заводит работу экран (правило
  /// `client-server.md`, §5.4), а знает о ней и источник — и собирать доводы
  /// дважды значило бы однажды собрать их по-разному.
  ///
  /// Приёмник — сам источник: находки складываются прямо в него, и «передать
  /// накопленное» становится нечем и некуда (`file-search.md`, §4.2).
  static OperationSpec specFor(SearchAddress address) {
    final query = address.fullQuery;
    return OperationSpec(
      kind: kind,
      targets: Targets.paths([address.where]),
      destinationPath: address.toString(),
      options: {
        maskOption: query.mask,
        regexpOption: query.regexp,
        caseOption: query.caseSensitive,
        recursiveOption: query.recursive,
        hiddenOption: query.hidden,
        ignoreOption: query.ignore,
        followLinksOption: query.followLinks,
        if (query.sizeFrom case final from?) sizeFromOption: from,
        if (query.sizeTo case final to?) sizeToOption: to,
        if (query.changedAfter case final after?) changedAfterOption: after.millisecondsSinceEpoch,
        if (query.changedBefore case final before?) changedBeforeOption: before.millisecondsSinceEpoch,
        contentOption: query.content,
        contentRegexpOption: query.contentRegexp,
        contentCaseOption: query.contentCase,
        wholeWordsOption: query.wholeWords,
        allCharsetsOption: query.allCharsets,
      },
    );
  }

  /// Одна работа на все поиски, сколько бы их ни шло разом.
  static const String kind = 'search.find';

  /// Что набрано в поле имени: маска (`*.dart;!*.g.dart`) или выражение.
  static const String maskOption = 'mask';

  /// Читать набранное выражением, а не маской.
  static const String regexpOption = 'regexp';

  /// Различать ли регистр — в имени и в каталогах-исключениях.
  static const String caseOption = 'case';

  /// Заходить ли во вложенные каталоги.
  static const String recursiveOption = 'recursive';

  /// Брать ли скрытые объекты.
  static const String hiddenOption = 'hidden';

  /// Каталоги, в которые не заходить: маска имён.
  static const String ignoreOption = 'ignore';

  /// Спускаться ли в ссылки, ведущие в каталог.
  static const String followLinksOption = 'followLinks';

  /// Размер в байтах: от и до включительно.
  static const String sizeFromOption = 'sizeFrom';
  static const String sizeToOption = 'sizeTo';

  /// Изменён после и до — в миллисекундах эпохи: через границу едут значения,
  /// а `DateTime` значением протокола не является.
  static const String changedAfterOption = 'changedAfter';
  static const String changedBeforeOption = 'changedBefore';

  /// Что искать внутри файла и как читать набранное.
  static const String contentOption = 'content';
  static const String contentRegexpOption = 'contentRegexp';
  static const String contentCaseOption = 'contentCase';
  static const String wholeWordsOption = 'wholeWords';
  static const String allCharsetsOption = 'allCharsets';
}
