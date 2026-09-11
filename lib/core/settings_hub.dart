import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';

import 'settings_store.dart';

/// Настройки приложения: кто их держит и когда записывает.
///
/// **Файл принадлежит ядру.** Читать и писать его — это ввод-вывод, и делать
/// его там, где диска нет, неоткуда. Панельная половина настроек и так живёт
/// здесь: каталог, курсор, колонки и сортировка — это состояние сеанса.
/// Экранная — место окна, разделитель и активная панель — приезжает
/// рукопожатием и правится сообщением, а хранится всё равно тут
/// (`docs/spec/client-server.md`, §9).
///
/// Запись отложенная: подряд идущие изменения сливаются в одну.
class SettingsHub {
  SettingsHub({
    required this.store,
    required AppSettings stored,
    required PanelSettings? Function(PanelId panel) panelSettings,
    List<PanelLayout>? panels,
    List<int>? shown,
    this.saveDelay = defaultSaveDelay,
  }) : _stored = stored,
       _panelSettings = panelSettings,
       _ui = UiSettings(
         activePanel: stored.activePanel,
         splitRatio: stored.splitRatio,
         window: stored.window,
         sizeScanConcurrency: stored.sizeScanConcurrency,
         reconnectAtStartup: stored.reconnectAtStartup,
         dialogs: {...stored.dialogs},
         // Раскладку по сторонам знает тот, кто заводил сессии: файл говорит,
         // сколько их в каждой стороне, а какая личность досталась какой —
         // видно только оттуда (`docs/spec/panel-sessions.md`, §10).
         panels: panels ?? UiSettings.defaultPanels,
         shown: shown ?? UiSettings.defaultShown,
       ) {
    // Раздел модуля просит записать себя сам — тем же отложенным путём.
    _stored.modules.onSave = schedule;
    remember();
  }

  /// Через сколько после изменения настройки уходят на диск.
  static const Duration defaultSaveDelay = Duration(seconds: 1);

  final SettingsStore store;
  final Duration saveDelay;

  /// Прочитанное с диска — вместе с тем, чем ядро не заведует: разделами
  /// модулей и размером пула обхода. Терять их при записи нельзя.
  final AppSettings _stored;

  /// Настройки сессии; null — сессии больше нет, и в файл ей нечего писать.
  ///
  /// Меняется один раз: пока ядро собирается, отвечает карта заведённых
  /// сессий, а собравшись, ядро подменяет её собой — иначе заведённая на ходу
  /// сессия в файл бы не попала ([bindPanels]).
  PanelSettings? Function(PanelId panel) _panelSettings;

  UiSettings _ui;
  Timer? _timer;
  String? _savedSnapshot;
  String? _savedQuietSnapshot;

  /// То, что держит и правит экран: рукопожатие везёт именно это.
  ///
  /// Разделы модулей собираются на каждый вопрос: их правят по обе стороны, и
  /// снимок должен быть свежим, а не тем, с которым мы начинали.
  UiSettings get ui => _ui.copyWith(modules: serialize(_stored.modules));

  /// Настройки целиком — такими, какими они уйдут в файл.
  ///
  /// Собираются заново на каждый запрос: панели рассказывают о себе сами, а
  /// то, чем ядро не заведует, переносится из прочитанного.
  AppSettings get settings => AppSettings(
    panels: [
      for (final panel in _ui.panels)
        PanelGroupSettings(
          // Закрытая сессия в файл не попадает: раскладка приезжает с экрана и
          // может отстать от закрытия на одно сообщение.
          sessions: [
            for (final session in panel.sessions)
              if (_panelSettings(session) case final settings?) settings,
          ],
          current: panel.current,
          name: panel.name,
        ),
    ],
    shown: [..._ui.shown],
    activePanel: _ui.activePanel,
    splitRatio: _ui.splitRatio,
    sizeScanConcurrency: _ui.sizeScanConcurrency,
    reconnectAtStartup: _ui.reconnectAtStartup,
    window: _ui.window,
    dialogs: _ui.dialogs,
    modules: _stored.modules,
  );

  /// Подключаться ли при запуске к сохранённым удалённым источникам.
  bool get reconnectAtStartup => _ui.reconnectAtStartup;

  /// Личности показанных сессий: все столбцы показанных наборов.
  ///
  /// Ими и ограничивается чтение при запуске: непоказанный набор каталога не
  /// читает, пока его не покажут (`docs/spec/panel-sessions.md`, §6).
  Set<PanelId> get shownSessions => {
    for (final at in _ui.shown)
      if (at >= 0 && at < _ui.panels.length) ..._ui.panels[at].sessions,
  };

  /// Спрашивать о сессиях у ядра: оно одно знает, какие из них живы сейчас.
  ///
  /// Зовётся ядром при сборке — раньше некому, а сам хаб к тому времени уже
  /// нужен: ядро принимает его аргументом.
  void bindPanels(PanelSettings? Function(PanelId panel) lookup) => _panelSettings = lookup;

  /// Правка с той стороны: окно подвинули, разделитель потянули, панель
  /// переключили, поправили раздел модуля.
  ///
  /// Разделы дочитываются в **живые** объекты, а не подменяют их: ими
  /// пользуется и эта сторона — оболочка спрашивает, чем себя запускать, — и
  /// подмена оставила бы её со старым экземпляром.
  void applyUi(UiSettings values) {
    final same = _ui == values;
    if (values.modules.isNotEmpty) {
      _stored.modules.fromMap(values.modules);
    }
    if (same && values.modules.isEmpty) {
      return;
    }
    _ui = values;
    schedule();
  }

  /// Панель о себе рассказала.
  ///
  /// Курсор из сравнения исключён намеренно: иначе каждый шаг стрелкой заводил
  /// бы таймер записи, а ходят по панели постоянно. В файл он всё равно
  /// попадёт — вместе со следующей настоящей причиной записать и при выходе,
  /// где [save] сравнивает снимки целиком.
  void panelsChanged() {
    if (_snapshotWithoutCursor() != _savedQuietSnapshot) {
      schedule();
    }
  }

  /// Отложить запись: что-то изменилось, но ждать конца правок незачем.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(saveDelay, () => unawaited(save()));
  }

  /// Записать сейчас — если есть что.
  Future<void> save() async {
    _timer?.cancel();
    if (_snapshot() == _savedSnapshot) {
      return;
    }
    final values = settings;
    remember();
    await store.save(values);
  }

  /// Запомнить записанное состояние — оба снимка разом: полный, по которому
  /// решается сама запись, и тихий, по которому решается её планирование.
  void remember() {
    _savedSnapshot = _snapshot();
    _savedQuietSnapshot = _snapshotWithoutCursor();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  String _snapshot() => jsonEncode(serialize(settings));

  /// Тот же снимок, но без положения курсора.
  ///
  /// Ходит по наборам: в файле лежат наборы, а в них сессии
  /// (`docs/spec/panel-sessions.md`, §10), и положение курсора у каждой своё.
  String _snapshotWithoutCursor() {
    final map = serialize(settings);
    final panels = map['panels'];
    if (panels is List) {
      for (final panel in panels) {
        final sessions = panel is Map ? panel['sessions'] : null;
        if (sessions is! List) {
          continue;
        }
        for (final session in sessions) {
          if (session is Map) {
            session
              ..remove('cursor')
              // Путь курсора — то же положение, только для дерева: имени
              // там мало (`docs/spec/panel-node-list.md`, §3). Ради движения
              // курсора настройки на диск не пишутся.
              ..remove('cursorPath')
              // И прокрутка: это положение, а не настройка.
              ..remove('scroll');
          }
        }
      }
    }
    return jsonEncode(map);
  }
}
