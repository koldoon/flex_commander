import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import '../settings/settings_store.dart';
import 'panel_controller.dart';
import 'panel_viewport_registry.dart';
import 'app_view_controller.dart';
import 'view_registry.dart';
import 'credentials_controller.dart';
import 'theme_controller.dart';
import 'error_controller.dart';
import 'toast_controller.dart';

/// Состояние приложения — реализация [Application].
///
/// Ветвление «если активна левая, то…» живёт только здесь: панели друг о друге
/// не знают. Активная панель — источник операции, пассивная — её приёмник.
/// Команды видят приложение только как [Application].
class AppController extends ChangeNotifier implements Application {
  AppController({
    required this.left,
    required this.right,
    required this.store,
    required AppSettings settings,
    required this.commands,
    this.providers,
    PanelViewports? viewports,
    List<ViewerSpec> viewers = const [],
    List<NodeInfoProvider> nodeInfoProviders = const [],
    Views? views,
    ThemeController? theme,
    ToastController? toasts,
    CredentialsController? credentials,
    ErrorController? errors,
    WindowService? window,
    this.dragAndDrop,
    this.saveDelay = const Duration(seconds: 1),
  }) : _splitRatio = settings.splitRatio,
       _windowGeometry = settings.window,
       _initialSettings = settings,
       theme = theme ?? ThemeController(),
       toasts = toasts ?? ToastController(),
       credentials = credentials ?? CredentialsController(),
       errors = errors ?? ErrorController(),
       viewports = viewports ?? const NoPanelViewports(),
       // По убыванию приоритета — один раз при сборке: спрашивают этот список
       // на каждое открытие файла, а меняться ему больше негде.
       viewers = [...viewers]..sort((a, b) => b.priority.compareTo(a.priority)),
       nodeInfoProviders = [...nodeInfoProviders]..sort((a, b) => b.priority.compareTo(a.priority)),
       views = views ?? const NoViews(),
       window = window ?? const NoopWindowService() {
    // Одна панель активна всегда, ещё до первого чтения каталогов.
    left.setActive(settings.activePanel != 1);
    right.setActive(settings.activePanel == 1);
    left.addListener(_onPanelChanged);
    right.addListener(_onPanelChanged);
    // Модуль просит сохранить свой раздел тем же способом, что и панель:
    // отложенной записью, которая сливает подряд идущие изменения.
    _initialSettings.modules.onSave = _scheduleSave;
    this.window.addListener(_onWindowChanged);
    commands.attach(this);
  }

  /// Тип уточнён до реализации: приложение выставляет панелям признак
  /// активности и закрывает их при выходе — этого в [Panel] нет и не должно
  /// быть. Всем остальным, включая виджеты, хватает интерфейса.
  /// Что видно выше ряда функциональных кнопок. Сами панели тоже экран, и
  /// открывает его модуль: ядро не решает, чем показывать файлы.
  @override
  /// Рабочая область: что где стоит и кому принадлежит ввод.
  @override
  late final AppViewController view = AppViewController(this);

  @override
  final PanelController left;

  @override
  final PanelController right;
  final SettingsStore store;

  /// Действия приложения: за кнопкой нижней панели и за горячей клавишей
  /// стоит одна и та же команда.
  @override
  final CommandRegistry commands;

  /// Оформление приложения. Тип уточнён до реализации: приложение владеет
  /// службой и закрывает её при выходе, остальным хватает [ThemeService].
  @override
  final ThemeController theme;

  /// Чем рисуется содержимое панелей. Без интерфейса — ничем: приложению
  /// в тесте состояния или в сценарии рисовать нечем и незачем.
  @override
  final PanelViewports viewports;

  /// Объявленные просмотрщики, по убыванию приоритета.
  @override
  final List<ViewerSpec> viewers;

  /// Объявленные провайдеры сведений, по убыванию приоритета.
  @override
  final List<NodeInfoProvider> nodeInfoProviders;

  @override
  final Views views;

  /// Работы, ушедшие в фон. Их держит реестр команд: он и так знает про все
  /// запуски и их окна, а фон — это ровно «запуск без окна».
  @override
  Operations get operations => commands;

  /// Ошибки, которые никто не поймал: показать, а не только записать в журнал.
  @override
  final ErrorController errors;

  /// Всплывающие сообщения: о том, что случилось и уже закончилось.
  @override
  final ToastController toasts;

  /// Пароли и прочие секреты: спросить то, без чего дальше нельзя.
  @override
  final CredentialsController credentials;

  /// Окно приложения. Без управления окном (в тестах) — заглушка.
  @override
  final WindowService window;

  /// Перетаскивание мышью; null — модуля нет.
  @override
  final DragAndDrop? dragAndDrop;

  /// Задержка перед записью настроек. Настройки пишутся и при выходе, но
  /// отложенная запись бережёт их и при аварийном завершении.
  final Duration saveDelay;

  final AppSettings _initialSettings;

  double _splitRatio;
  WindowGeometry? _windowGeometry;
  Timer? _saveTimer;

  /// Записанное состояние целиком — по нему решается, нужна ли запись вообще.
  String? _savedSnapshot;

  /// Оно же без положения курсора — по нему решается, планировать ли
  /// отложенную запись: ходьба по панели сама по себе на диск не пишет.
  String? _savedQuietSnapshot;

  /// Активная панель: в ней курсор и ввод с клавиатуры.
  @override
  PanelController get activePanel => left.active ? left : right;

  /// Пассивная панель — приёмник операций копирования и перемещения.
  @override
  PanelController get passivePanel => left.active ? right : left;

  /// Доля ширины окна под левой панелью.
  @override
  double get splitRatio => _splitRatio;

  /// Последняя известная геометрия окна.
  @override
  WindowGeometry? get windowGeometry => _windowGeometry;

  /// Запоминает геометрию окна.
  ///
  /// У развёрнутого окна размеры совпадают с экраном, поэтому запоминается не
  /// они, а те, к которым окно вернётся после сворачивания — иначе оно так и
  /// осталось бы во весь экран.
  void setWindowGeometry(WindowGeometry? geometry) {
    if (geometry == null) {
      return;
    }
    final previous = _windowGeometry;
    final updated = geometry.maximized && previous != null ? previous.copyWith(maximized: true) : geometry;

    if (_windowGeometry == updated) {
      return;
    }
    _windowGeometry = updated;
    _scheduleSave();
  }

  @override
  void activate(Panel panel) {
    assert(panel == left || panel == right, 'Панель не принадлежит этому приложению');
    // Ввод мог быть у командной строки — тогда «сделать активной ту же самую
    // панель» означает вернуть его ей, и ранний выход ниже пропустил бы это:
    // щелчок по активной панели не выводил бы из строки.
    final released = view.releaseFocus();
    if (panel.active) {
      if (released) {
        notifyListeners();
      }
      return;
    }
    left.setActive(panel == left);
    right.setActive(panel == right);
    notifyListeners();
  }

  /// Переключить активную панель (Tab).
  @override
  /// `Tab`: ввод переходит в **соседнюю область**, а не в соседнюю панель.
  ///
  /// Разница видна там, где панель накрыта наложением: быстрый просмотр стоит
  /// напротив курсора, и `Tab` уводит ввод в него — со всеми клавишами
  /// просмотрщика, как если бы он был во весь экран. Активировать спрятанную
  /// под ним панель было бы хуже всего: курсор ушёл бы туда, где его не видно.
  ///
  /// Что стоит в области — панель или наложение, — решает не эта команда:
  /// `setFocus` сам зовёт `activate` там, где панель есть.
  ///
  /// Из области, которая панелью не является вовсе (полноэкранное, командная
  /// строка), переход идёт к панели напротив источника — как и раньше.
  void toggleActivePanel() {
    final active = view.activeArea;
    view.setFocus(active.isPanelArea ? active.opposite : view.sourceArea.opposite);
  }

  /// Раздел настроек модуля: ядро в него не заглядывает, только хранит.
  @override
  SettingsScope moduleSettings(String namespace) => _initialSettings.modules.scope(namespace);

  /// Окна команд держит реестр — он же их и создаёт.

  @override
  void setSplitRatio(double value) {
    final clamped = value.clamp(AppSettings.minSplitRatio, AppSettings.maxSplitRatio);
    if (_splitRatio == clamped) {
      return;
    }
    _splitRatio = clamped;
    notifyListeners();
    _scheduleSave();
  }

  /// Открывает сохранённые каталоги и активирует панель, которая была активной
  /// в прошлый раз. Недоступный путь заменяется корнем провайдера, чтобы
  /// приложение всегда стартовало в рабочем состоянии.
  @override
  Future<void> start() async {
    _rememberSaved();
    await window.restore(_initialSettings.window);

    await Future.wait([_openPanel(left, _initialSettings.left.path), _openPanel(right, _initialSettings.right.path)]);

    activate(_initialSettings.activePanel == 1 ? right : left);
    // Первый кадр показывается уже с восстановленным состоянием, поэтому
    // отложенную запись, вызванную открытием каталогов, отменяем.
    _saveTimer?.cancel();
    _rememberSaved();
  }

  /// Реестр провайдеров; null — приложение собрано без него (тест состояния).
  ///
  /// Нужен ровно для одного: на выходе закрыть всё смонтированное, не
  /// спрашивая счётчиков. Спорить там не с кем, а открытый файл или живое
  /// соединение пережить процесс не должны. Наружу отдаётся ради проверок:
  /// `providers.mounted` отвечает на вопрос «что осталось открытым».
  final ProviderRegistry? providers;

  /// Сохраняет настройки и останавливает незавершённые операции.
  @override
  Future<void> shutdown() async {
    _saveTimer?.cancel();
    left.cancel();
    right.cancel();
    await commands.shutdown();
    // Геометрию здесь не спрашиваем: выход происходит внутри системного
    // обработчика завершения, и обращение к плагину через платформенный канал
    // в этот момент приводит к взаимной блокировке — приложение перестаёт
    // закрываться. Сохраняется последнее известное состояние, а обновляет его
    // captureWindowGeometry.
    await save();

    // Последним — источники: до этого момента фоновые работы ещё могли из них
    // читать, а панели — сохранять свои пути.
    await providers?.disposeAll();
  }

  /// Текущее состояние приложения в виде сохраняемых настроек.
  /// Текущее состояние приложения в виде сохраняемых настроек.
  ///
  /// Собирается заново на каждый запрос — панели и окно рассказывают о себе
  /// сами. А то, чем приложение не заведует, переносится из прочитанного:
  /// разделы модулей и размер пула обхода каталогов ядро не меняет, но и
  /// терять их при записи не должно.
  @override
  AppSettings get settings => AppSettings(
    left: left.settings,
    right: right.settings,
    activePanel: left.active ? 0 : 1,
    splitRatio: _splitRatio,
    sizeScanConcurrency: _initialSettings.sizeScanConcurrency,
    window: _windowGeometry,
    modules: _initialSettings.modules,
  );

  Future<void> save() async {
    if (_snapshot() == _savedSnapshot) {
      return;
    }
    _rememberSaved();
    await store.save(settings);
  }

  Future<void> _openPanel(PanelController panel, String path) async {
    // Без подключения: восстановление состояния не должно ходить в сеть.
    // Сохранённый адрес сервера означал бы вопрос о пароле поверх ещё пустых
    // панелей, а недоступный сервер — ожидание до истечения времени
    // подключения при каждом запуске. На сервер человек возвращается сам —
    // так же ведут себя Total Commander и Far.
    if (path.isNotEmpty && await panel.openPath(path, allowConnect: false)) {
      return;
    }
    if (await panel.openPath(panel.provider.homePath)) {
      return;
    }
    await panel.open(panel.provider.rootDirectory);
  }

  /// Панели уведомляют обо всём, включая движение курсора, поэтому запись
  /// планируется только при изменении того, что действительно сохраняется.
  /// Спрашивает у окна его текущую геометрию и запоминает её.
  ///
  /// Вызывается на изменения окна и при уходе приложения на второй план —
  /// то есть заведомо не в момент завершения процесса.
  Future<void> captureWindowGeometry() async {
    setWindowGeometry(await window.current());
  }

  void _onWindowChanged() => unawaited(captureWindowGeometry());

  void _onPanelChanged() {
    // Курсор из сравнения исключён намеренно: иначе каждый шаг стрелкой заводил
    // бы таймер записи, а ходят по панели постоянно. В файл он всё равно
    // попадёт — вместе со следующей настоящей причиной записать и при выходе,
    // где `save` сравнивает снимки целиком.
    if (_snapshotWithoutCursor() != _savedQuietSnapshot) {
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(save()));
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

  /// Запоминает записанное состояние — оба снимка разом: полный, по которому
  /// решается сама запись, и тихий, по которому решается её планирование.
  void _rememberSaved() {
    _savedSnapshot = _snapshot();
    _savedQuietSnapshot = _snapshotWithoutCursor();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    toasts.dispose();
    credentials.dispose();
    left.removeListener(_onPanelChanged);
    right.removeListener(_onPanelChanged);
    window.removeListener(_onWindowChanged);
    super.dispose();
  }
}
