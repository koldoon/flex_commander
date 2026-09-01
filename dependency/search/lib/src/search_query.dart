import 'package:fc_api/fc_api.dart';

/// О чём спрашивают: маска имени и где искать.
///
/// Каталог — не поле, а то, где стоит панель: чтобы искать в другом месте,
/// туда переходят панелью. Так не бывает поиска «не там, где думает человек».
class SearchQuery {
  const SearchQuery({required this.mask, this.recursive = true, this.hidden = false});

  /// Образцы через `;`, `!` исключает — тот же движок, что у пометки.
  final String mask;

  /// Заходить ли во вложенные каталоги.
  final bool recursive;

  /// Брать ли скрытые объекты.
  final bool hidden;

  /// Ищем ли хоть что-нибудь: пустая маска не совпадает ни с чем.
  bool get isEmpty => FileMask.parse(mask).isEmpty;

  SearchQuery copyWith({String? mask, bool? recursive, bool? hidden}) =>
      SearchQuery(mask: mask ?? this.mask, recursive: recursive ?? this.recursive, hidden: hidden ?? this.hidden);
}
