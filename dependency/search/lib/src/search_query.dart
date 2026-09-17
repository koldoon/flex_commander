import 'package:fc_api/fc_api.dart';

/// О чём спрашивают: что искать и по каким условиям отбирать.
///
/// Каталог — не поле, а то, где стоит панель: чтобы искать в другом месте,
/// туда переходят панелью. Так не бывает поиска «не там, где думает человек».
///
/// Условия отбора — `docs/spec/file-search.md`, §10.
class SearchQuery {
  const SearchQuery({
    required this.mask,
    this.regexp = false,
    this.caseSensitive = false,
    this.recursive = true,
    this.hidden = false,
    this.ignore = '',
    this.followLinks = false,
    this.sizeFrom,
    this.sizeTo,
    this.changedAfter,
    this.changedBefore,
  });

  /// Что набрано в поле имени — как набрано.
  ///
  /// Маска (`*.dart;!*.g.dart`) или выражение — решает [regexp]; разбирает то
  /// и другое `NameRule`.
  final String mask;

  /// Читать набранное выражением, а не маской.
  final bool regexp;

  /// Различать ли регистр — и в имени, и в каталогах-исключениях: один флажок
  /// на окно, двух правил в нём не нужно.
  final bool caseSensitive;

  /// Заходить ли во вложенные каталоги.
  final bool recursive;

  /// Брать ли скрытые объекты.
  final bool hidden;

  /// Каталоги, в которые не заходить: маска **имён**, а не путей.
  final String ignore;

  /// Спускаться ли в ссылки, ведущие в каталог.
  final bool followLinks;

  /// Размер в байтах: от и до включительно; null — без ограничения.
  final int? sizeFrom;
  final int? sizeTo;

  /// Изменён после и до; null — без ограничения.
  final DateTime? changedAfter;
  final DateTime? changedBefore;

  /// Правило имени — разобранное.
  NameRule get name => NameRule.parse(mask, regexp: regexp, caseSensitive: caseSensitive);

  /// Маска каталогов-исключений — разобранная. Пустая не исключает ничего.
  FileMask get ignored => FileMask.parse(ignore, caseSensitive: caseSensitive);

  /// Ищем ли хоть что-нибудь: пустое правило не совпадает ни с чем.
  bool get isEmpty => name.isEmpty;

  /// Годится ли запрос к отправке. Неверное выражение — не отказ по нажатию, а
  /// ошибка у поля (`file-search.md`, §10.2).
  bool get isValid => name.isValid;

  SearchQuery copyWith({
    String? mask,
    bool? regexp,
    bool? caseSensitive,
    bool? recursive,
    bool? hidden,
    String? ignore,
    bool? followLinks,
    int? Function()? sizeFrom,
    int? Function()? sizeTo,
    DateTime? Function()? changedAfter,
    DateTime? Function()? changedBefore,
  }) => SearchQuery(
    mask: mask ?? this.mask,
    regexp: regexp ?? this.regexp,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    recursive: recursive ?? this.recursive,
    hidden: hidden ?? this.hidden,
    ignore: ignore ?? this.ignore,
    followLinks: followLinks ?? this.followLinks,
    // Способом, а не значением: у этих полей «не задано» — законное значение,
    // и обычным `?:` его не отличить от «не трогай».
    sizeFrom: sizeFrom == null ? this.sizeFrom : sizeFrom(),
    sizeTo: sizeTo == null ? this.sizeTo : sizeTo(),
    changedAfter: changedAfter == null ? this.changedAfter : changedAfter(),
    changedBefore: changedBefore == null ? this.changedBefore : changedBefore(),
  );
}
