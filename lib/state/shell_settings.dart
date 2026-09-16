import 'package:fc_api/fc_api.dart';

/// Что помнит о себе сама оболочка.
///
/// Своего модуля у ядра нет, а помнить есть что: раздел называется `fc.shell` и
/// живёт по тем же правилам, что и разделы модулей.
class ShellSettings implements Serializable {
  ShellSettings({
    this.language = 'system',
    this.allowElevatedWrites = true,
    this.useBuiltinExtensions = true,
    this.listingCache = true,
    this.sessionsInTitleBar = true,
    this.listingCacheLimit = defaultListingCacheLimit,
    this.listingCacheTtl = defaultListingCacheTtl,
    this.watchDirectories = true,
    this.watchDelay = defaultWatchDelay,
    List<String>? compoundExtensions,
    List<String>? recentCommands,
  }) : compoundExtensions = compoundExtensions ?? <String>[],
       recentCommands = recentCommands ?? <String>[];

  /// Составные расширения, дописанные человеком: `cfg.json`, `story.tsx`.
  ///
  /// Идут **впереди** встроенных: своё можно поставить над общим, а не спорить
  /// с ним.
  List<String> compoundExtensions;

  /// Учитывать ли встроенный список (`tar.gz`, `spec.ts`, `min.js`…).
  bool useBuiltinExtensions;

  /// Предлагать ли запись от администратора там, где обычных прав не хватило.
  ///
  /// Выключенная — предложения нет вовсе, и отказ остаётся отказом. На общей
  /// машине это единственный честный ответ. Живёт здесь, а не у локальной ФС:
  /// повышение работает и на той стороне `ssh`, и настройка у него общая.
  bool allowElevatedWrites;

  /// Сколько каталогов помнить, когда предела не назвали.
  static const int defaultListingCacheLimit = 64;

  /// Сколько секунд запись годится к показу, когда срока не назвали.
  static const int defaultListingCacheTtl = 300;

  /// Язык интерфейса: `system`, `en` или `ru`.
  ///
  /// `system` — не «неизвестно», а выбор: язык берётся у машины, и переехавшее
  /// на другую машину приложение заговорит по-местному
  /// (`docs/spec/localization.md`, §9).
  String language;

  /// Показывать ли каталог, где панель уже была, сразу из памяти.
  ///
  /// Включён по умолчанию: выключенный никто бы не проверил, а выигрыш он даёт
  /// там же, где и риск, — на медленном источнике. Настройка остаётся ради
  /// случая «вижу устаревшее и хочу разобраться»: один флаг вместо разговора о
  /// том, кеш это или провайдер (`docs/spec/listing-cache.md`, §10).
  bool listingCache;

  /// Сколько каталогов помнить. Лишние вытесняются по давности.
  int listingCacheLimit;

  /// Сколько секунд запись годится к показу. Дальше панель ждёт чтения, как
  /// ждала до кеша: показать список получасовой давности значит показать
  /// неправду и не заметить этого.
  int listingCacheTtl;

  /// Следить ли за показанным каталогом и догонять чужие изменения.
  ///
  /// Включено: выключенного никто бы не проверил, а без слежения панель
  /// показывает снимок — то, ради чего этап и затевался
  /// (`docs/spec/directory-watch.md`). Выключают его те, кому дорог покой
  /// диска: остаётся `Cmd-R`.
  bool watchDirectories;

  /// Сколько миллисекунд копить события, прежде чем перечитать.
  ///
  /// Одно осмысленное изменение присылает несколько событий — переименование
  /// четыре, распаковка двухсот файлов четыре сотни, — и реагировать на каждое
  /// значит читать каталог без нужды.
  int watchDelay;

  /// Умолчание — то же число, каким живёт сам накопитель: два места, называющих
  /// одно, однажды разойдутся.
  static const int defaultWatchDelay = 300;

  /// Показывать ли ряд открытых наборов в полосе заголовка.
  ///
  /// Включено: полоса до него пустовала, и места ряд ни у кого не отнимает
  /// (`docs/spec/panel-sessions.md`, §3). Выключают его те, кто держит свои два
  /// набора в голове: переключение остаётся окном, `Ctrl-Tab` и номерами.
  bool sessionsInTitleBar;

  /// Недавно запущенные команды, свежие впереди.
  ///
  /// Это состояние, а не выбор: в окне настроек его нет — как нет там истории
  /// команд и путей панелей.
  List<String> recentCommands;

  @override
  void fromMap(Map<String, dynamic> m) {
    language = extract(language, m['language']);
    allowElevatedWrites = extract(allowElevatedWrites, m['allowElevatedWrites']);
    listingCache = extract(listingCache, m['listingCache']);
    sessionsInTitleBar = extract(sessionsInTitleBar, m['sessionsInTitleBar']);
    listingCacheLimit = extract(listingCacheLimit, m['listingCacheLimit']).clamp(1, 4096);
    listingCacheTtl = extract(listingCacheTtl, m['listingCacheTtl']).clamp(1, 86400);
    watchDirectories = extract(watchDirectories, m['watchDirectories']);
    watchDelay = extract(watchDelay, m['watchDelay']).clamp(50, 5000);
    useBuiltinExtensions = extract(useBuiltinExtensions, m['useBuiltinExtensions']);
    compoundExtensions = extractList<String>(m['compoundExtensions']);
    recentCommands = extractList<String>(m['recentCommands']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['language'] = language;
    m['allowElevatedWrites'] = allowElevatedWrites;
    m['listingCache'] = listingCache;
    m['sessionsInTitleBar'] = sessionsInTitleBar;
    m['listingCacheLimit'] = listingCacheLimit;
    m['listingCacheTtl'] = listingCacheTtl;
    m['watchDirectories'] = watchDirectories;
    m['watchDelay'] = watchDelay;
    m['useBuiltinExtensions'] = useBuiltinExtensions;
    m['compoundExtensions'] = compoundExtensions;
    m['recentCommands'] = recentCommands;
  }
}
