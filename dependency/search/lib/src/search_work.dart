/// Как зовут работу поиска и её доводы.
///
/// Отдельным файлом, потому что имена нужны **обеим** сторонам: экран собирает
/// заявку, ядро по ней узнаёт свою работу. Здесь только строки — ни дерева, ни
/// провайдеров, — и потому этот файл видят обе половины модуля, не таща за
/// собой чужой половины (`docs/spec/client-server.md`, §8).
abstract final class SearchWork {
  /// Одна работа на все поиски, сколько бы их ни шло разом.
  static const String kind = 'search.find';

  /// Образцы через `;`, `!` исключает.
  static const String maskOption = 'mask';

  /// Заходить ли во вложенные каталоги.
  static const String recursiveOption = 'recursive';

  /// Брать ли скрытые объекты.
  static const String hiddenOption = 'hidden';
}
