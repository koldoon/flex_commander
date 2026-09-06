import 'dart:collection';

import 'package:fc_core_api/fc_core_api.dart';

/// Списки каталогов, которые панель уже читала.
///
/// Спецификация — `docs/spec/listing-cache.md`.
///
/// Главное правило: **запись здесь — подсказка, а не источник правды**.
/// Показанное из памяти всегда догоняется чтением, поэтому ни одна команда о
/// кеше не знает и ни одна не вправе на него опереться. Отсюда и всё
/// остальное: кеш ничего не арендует, файловые операции его не трогают, а
/// выключенный он возвращает поведение, которое было до него.
///
/// Один на приложение: каталог, прочитанный левой панелью, достаётся правой
/// даром — обе стоят рядом в одном дереве чаще, чем в разных.
class ListingCache {
  ListingCache({
    required bool Function() enabled,
    required int Function() limit,
    required Duration Function() ttl,
    DateTime Function()? clock,
  }) : _enabled = enabled,
       _limit = limit,
       _ttl = ttl,
       _clock = clock ?? DateTime.now;

  /// Настройки приходят способом узнать, а не значением: их правят в окне, и
  /// следующий же переход должен идти по новому правилу. Умолчания лежат там
  /// же, где сами настройки, — в разделе оболочки.
  final bool Function() _enabled;
  final int Function() _limit;
  final Duration Function() _ttl;

  /// Часы — снаружи: срок годности проверяется в тестах, а ждать пять минут
  /// они не станут.
  final DateTime Function() _clock;

  /// Порядок обращения: первый ключ — самый давний, его и вытесняют.
  final LinkedHashMap<String, _Listing> _entries = LinkedHashMap();

  /// Сколько каталогов помнится сейчас. Нужно проверкам: снаружи о размере
  /// памяти спрашивать некому.
  int get length => _entries.length;

  /// Что показать сразу; null — показывать нечего, панель читает как читала.
  ///
  /// Просроченная запись не отдаётся и выбрасывается: мгновенно показать
  /// список получасовой давности значит показать неправду и не заметить этого.
  List<FsNode>? take(DirectoryNode dir, {required bool includeHidden}) {
    if (!_enabled()) {
      return null;
    }
    final key = _keyOf(dir.pathString, includeHidden);
    final entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (_clock().difference(entry.readAt) > _ttl()) {
      _entries.remove(key);
      return null;
    }
    // Список принадлежит провайдеру, а не пути: одинаковые пути в двух разных
    // источниках одной схемы — это разные каталоги. Чужой список не отдаётся, а
    // запись остаётся на месте: следующее чтение её и подменит.
    if (!identical(entry.provider, dir.provider)) {
      return null;
    }
    // Обратно в конец: вытесняется давно не нужное, а не давно прочитанное.
    _entries.remove(key);
    _entries[key] = entry;
    return entry.nodes;
  }

  /// Запомнить прочитанное. Кладётся оно само — панель читает каталог перед
  /// тем, как в него войти, и отдельного прогрева не нужно.
  void put(DirectoryNode dir, List<FsNode> nodes, {required bool includeHidden}) {
    if (!_enabled()) {
      return;
    }
    final limit = _limit();
    if (limit <= 0) {
      return;
    }
    final key = _keyOf(dir.pathString, includeHidden);
    _entries.remove(key);
    while (_entries.length >= limit) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _Listing(List.unmodifiable(nodes), dir.provider, _clock());
  }

  /// Забыть каталог — обе его записи разом: показ скрытых входит в ключ, а
  /// «перечитать» просят про каталог, а не про то, как его показывали.
  void forget(DirectoryNode dir) {
    _entries.remove(_keyOf(dir.pathString, true));
    _entries.remove(_keyOf(dir.pathString, false));
  }

  /// Провайдера закрыли: всё, что он давал, — ссылки на мертвеца.
  ///
  /// Подписывается на это сборка приложения ([ProviderRegistry.onProviderClosed]):
  /// сам кеш аренды не берёт и о жизни провайдеров узнаёт со стороны.
  void forgetProvider(TreeProvider provider) {
    _entries.removeWhere((_, entry) => identical(entry.provider, provider));
  }

  void clear() => _entries.clear();

  /// Показ скрытых — часть ключа, а не поле записи: список без скрытых не
  /// годится панели, которая их показывает, и наоборот.
  ///
  /// Путь — машинный: он несёт схему (`fs:/…`, `ssh://user@host/…`,
  /// `/home/a.zip:zip:/inner`), поэтому два сервера, два архива и одинаковые
  /// пути в разных источниках не сливаются.
  static String _keyOf(String path, bool includeHidden) => includeHidden ? '+$path' : '-$path';
}

/// Прочитанный список: узлы, чей это провайдер и когда его читали.
class _Listing {
  _Listing(this.nodes, this.provider, this.readAt);

  final List<FsNode> nodes;

  /// По нему запись выбрасывается, когда провайдер закрыт. Ссылка держится, но
  /// аренды за ней нет: держать открытым архив, в который заглянули один раз,
  /// кешу не по чину.
  final TreeProvider provider;

  final DateTime readAt;
}
