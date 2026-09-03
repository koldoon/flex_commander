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
    required PanelSettings Function(PanelId panel) panelSettings,
    this.saveDelay = defaultSaveDelay,
  }) : _stored = stored,
       _panelSettings = panelSettings,
       _ui = UiSettings(
         activePanel: stored.activePanel,
         splitRatio: stored.splitRatio,
         window: stored.window,
         sizeScanConcurrency: stored.sizeScanConcurrency,
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

  final PanelSettings Function(PanelId panel) _panelSettings;

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
    left: _panelSettings(PanelId.left),
    right: _panelSettings(PanelId.right),
    activePanel: _ui.activePanel,
    splitRatio: _ui.splitRatio,
    sizeScanConcurrency: _ui.sizeScanConcurrency,
    window: _ui.window,
    modules: _stored.modules,
  );

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
  String _snapshotWithoutCursor() {
    final map = serialize(settings);
    final panels = map['panels'];
    if (panels is List) {
      for (final panel in panels) {
        if (panel is Map) {
          panel.remove('cursor');
        }
      }
    }
    return jsonEncode(map);
  }
}
