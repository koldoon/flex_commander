import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import '../core/core_server.dart';
import '../link/link.dart';
import '../ui/remote_content.dart';
import '../ui/remote_shell.dart';
import '../ui/remote_operation.dart';
import '../ui/session_mirror.dart';
import 'panel_viewport_registry.dart';
import 'app_view_controller.dart';
import 'view_registry.dart';
import '../ui/credentials_prompt.dart';
import '../ui/elevation_prompt.dart';
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
    required List<SessionMirror> sessions,
    List<PanelLayout>? panels,
    List<int>? shown,
    this.core,
    this.link,
    required AppSettings settings,
    required this.commands,
    PanelViewports? viewports,
    PanelViews? panelViews,
    List<ViewerSpec> viewers = const [],
    List<NodeInfoProvider> nodeInfoProviders = const [],
    Views? views,
    ThemeController? theme,
    StringsRegistry? strings,
    ToastController? toasts,
    CredentialsController? credentials,
    ElevationPrompt? elevation,
    FileNaming? fileNaming,
    ErrorController? errors,
    WindowService? window,
    this.dragAndDrop,
    this.contentTypes,
    this.fileIcons,
  }) : _panels = _panelsOf(sessions, panels),
       _shown = [...(shown ?? UiSettings.defaultShown)],
       _splitRatio = settings.splitRatio,
       _windowGeometry = settings.window,
       _initialSettings = settings,
       theme = theme ?? ThemeController(),
       // Своих нет — значит английский, тот же, что написан в коде.
       strings = strings ?? StringsRegistry(),
       toasts = toasts ?? ToastController(),
       // Своё, если не дали: подставке в тестах спрашивать некому и незачем.
       credentials = credentials ?? CredentialsController(onAnswer: _noAnswer),
       _elevation = elevation,
       fileNaming = fileNaming ?? const ReferenceFileNaming(),
       errors = errors ?? ErrorController(),
       viewports = viewports ?? const NoPanelViewports(),
       // Ни одного вида — панель рисует таблицей: так собирают приложение без
       // модуля панелей, и это не ошибка.
       panelViews = panelViews ?? PanelViewRegistry(),
       // По убыванию приоритета — один раз при сборке: спрашивают этот список
       // на каждое открытие файла, а меняться ему больше негде.
       viewers = [...viewers]..sort((a, b) => b.priority.compareTo(a.priority)),
       nodeInfoProviders = [...nodeInfoProviders]..sort((a, b) => b.priority.compareTo(a.priority)),
       views = views ?? const NoViews(),
       window = window ?? const NoopWindowService() {
    // Одна панель активна всегда, ещё до первого чтения каталогов.
    _applyActive(settings.activePanel == 1 ? right : left);
    // Слушать панели ради записи больше незачем: их настройки — это состояние
    // сеанса, и ядро видит его раньше и точнее (`spec/client-server.md`, §9).
    this.window.addListener(_onWindowChanged);
    commands.attach(this);
  }

  /// Тип уточнён до реализации: приложение выставляет панелям признак
  /// активности и закрывает их при выходе — этого в [Session] нет и не должно
  /// быть. Всем остальным, включая виджеты, хватает интерфейса.
  /// Что видно выше ряда функциональных кнопок. Сами панели тоже экран, и
  /// открывает его модуль: ядро не решает, чем показывать файлы.
  @override
  /// Рабочая область: что где стоит и кому принадлежит ввод.
  @override
  late final AppViewController view = AppViewController(this);

  /// Открытые наборы — одним списком на приложение
  /// (`docs/spec/panel-sessions.md`, §3).
  final List<_Panel> _panels;

  /// Номера показанных наборов: слева и справа.
  ///
  /// Один и тот же номер с обеих сторон — обычное дело: набор показывают, а не
  /// отдают во владение.
  final List<int> _shown;

  /// Наборы по раскладке из настроек; сессия, которой в раскладке нет, в набор
  /// не попадает, а пустым список не бывает — раскладки нет, значит на каждую
  /// сессию по набору.
  static List<_Panel> _panelsOf(List<SessionMirror> all, List<PanelLayout>? layout) {
    final byId = {for (final session in all) session.id: session};
    final panels = [
      for (final panel in layout ?? UiSettings.defaultPanels)
        if ([
              for (final id in panel.sessions)
                if (byId[id] case final session?) session,
            ]
            case final sessions when sessions.isNotEmpty)
          _Panel(sessions: sessions, current: panel.current, name: panel.name),
    ];
    return panels.isEmpty
        ? [
          for (final session in all) _Panel(sessions: [session], current: 0, name: ''),
        ]
        : panels;
  }

  @override
  List<Panel> get panels => List.unmodifiable(_panels);

  @override
  SessionMirror get left => _panelAt(ViewportPosition.left).shown;

  @override
  SessionMirror get right => _panelAt(ViewportPosition.right).shown;

  /// Все сессии всех наборов: их закрывают на выходе и о них рассказывают ядру.
  Iterable<SessionMirror> get _allSessions => _panels.expand((panel) => panel.columns);

  int _sideOf(ViewportPosition side) => side == ViewportPosition.right ? 1 : 0;

  @override
  Panel panelAt(ViewportPosition side) => _panelAt(side);

  /// То же, но своим типом: внутри нужен показанный столбец.
  _Panel _panelAt(ViewportPosition side) {
    final at = _sideOf(side);
    final number = (at < _shown.length ? _shown[at] : at).clamp(0, _panels.length - 1);
    return _panels[number];
  }

  @override
  Panel? panelOf(Session session) {
    for (final panel in _panels) {
      if (panel.columns.contains(session)) {
        return panel;
      }
    }
    return null;
  }

  /// Завести сессию по образцу; null — ядра нет или оно не умеет.
  Future<SessionMirror?> _createSession(Session like) async {
    if (like is! SessionMirror) {
      return null;
    }
    final opened = await link?.call(OpenPanel(like.id));
    if (opened is! PanelOpened) {
      return null;
    }
    return SessionMirror(id: opened.panel, link: link!, state: opened.state, listing: opened.listing, strings: strings);
  }

  @override
  Future<Panel> openPanel(ViewportPosition side, {Session? like, int? at}) async {
    final here = _panelAt(side);
    final model = like is SessionMirror ? like : here.shown;
    final session = await _createSession(model);
    if (session == null) {
      return here;
    }
    final panel = _Panel(sessions: [session], current: 0, name: '');
    // Рядом с нынешним, а не в конце списка: новый набор про то же место.
    final place = (at ?? _panels.indexOf(here) + 1).clamp(0, _panels.length);
    _panels.insert(place, panel);
    for (var i = 0; i < _shown.length; i++) {
      if (_shown[i] >= place) {
        _shown[i]++;
      }
    }
    showPanel(side, panel);
    return panel;
  }

  @override
  void closePanel(Panel panel) {
    if (panel is! _Panel) {
      return;
    }
    final gone = _panels.indexOf(panel);
    if (gone < 0) {
      return;
    }
    final wasActive = panel.columns.any((session) => session.active);
    // Панель без набора не бывает: закрыли последний — на его место встаёт
    // новый, там же (`docs/spec/panel-sessions.md`, §5). Заводится он **до**
    // закрытия: образцом ядру служит живая сессия, а закрытой уже нет.
    if (_panels.length == 1) {
      unawaited(_replaceLast(panel));
      return;
    }
    _panels.removeAt(gone);
    for (final session in panel.columns) {
      session.close();
    }
    for (var i = 0; i < _shown.length; i++) {
      if (_shown[i] > gone) {
        _shown[i]--;
      } else if (_shown[i] == gone) {
        _shown[i] = gone.clamp(0, _panels.length - 1);
      }
    }
    if (wasActive) {
      _applyActive(_panelAt(_activePanel == 1 ? ViewportPosition.right : ViewportPosition.left).shown);
    }
    _panelsChanged();
  }

  /// Закрывают единственный набор: на его место заводится такой же.
  ///
  /// Заводить нечем (ядра нет) — набор остаётся: пустой список панелям
  /// показывать нечем, и это хуже, чем незакрытый набор.
  Future<void> _replaceLast(_Panel gone) async {
    final session = await _createSession(gone.shown);
    if (session == null || !_panels.contains(gone)) {
      return;
    }
    _panels
      ..clear()
      ..add(_Panel(sessions: [session], current: 0, name: ''));
    for (var i = 0; i < _shown.length; i++) {
      _shown[i] = 0;
    }
    for (final column in gone.columns) {
      column.close();
    }
    _applyActive(session);
    _panelsChanged();
  }

  @override
  void showPanel(ViewportPosition side, Panel panel) {
    final number = panel is _Panel ? _panels.indexOf(panel) : -1;
    if (number < 0) {
      return;
    }
    final at = _sideOf(side);
    final wasActive = _panelAt(side).shown.active;
    _shown[at] = number;
    if (wasActive) {
      _applyActive(_panelAt(side).shown);
    }
    _wake(_panels[number]);
    _panelsChanged();
  }

  /// Показали набор — прочитать его сессии, если их ещё не читали.
  ///
  /// Ленивое чтение: при запуске ядро читает только показанные, остальные ждут
  /// этой просьбы (`docs/spec/panel-sessions.md`, §6). Прочитанной она ничего
  /// не стоит, поэтому проверять «а холодная ли она» здесь не нужно: об этом
  /// знает та сторона.
  void _wake(_Panel panel) {
    for (final column in panel.columns) {
      unawaited(link?.call(RestorePanel(column.id)) ?? Future<void>.value());
    }
  }

  @override
  void renamePanel(Panel panel, String name) {
    if (panel is! _Panel || panel.name == name) {
      return;
    }
    panel.name = name;
    _panelsChanged();
  }

  @override
  Future<Session> openSession(Panel panel, {Session? like, int? at}) async {
    if (panel is! _Panel) {
      return panel.session;
    }
    final model = like is SessionMirror ? like : panel.shown;
    final session = await _createSession(model);
    if (session == null) {
      return panel.shown;
    }
    final place = (at ?? panel.columns.length).clamp(0, panel.columns.length);
    panel.columns.insert(place, session);
    // Показанный столбец остаётся показанным: заведение не переводит взгляд.
    if (place <= panel.current) {
      panel.current++;
    }
    _panelsChanged();
    return session;
  }

  @override
  void closeSession(Session session) {
    final panel = panelOf(session);
    // Последний столбец не закрывается: набор без сессии — то же, что панель
    // без набора.
    if (panel is! _Panel || panel.columns.length < 2 || session is! SessionMirror) {
      return;
    }
    final gone = panel.columns.indexOf(session);
    panel.columns.removeAt(gone);
    if (panel.current >= panel.columns.length) {
      panel.current = panel.columns.length - 1;
    } else if (gone < panel.current) {
      panel.current--;
    }
    final wasActive = session.active;
    session.close();
    if (wasActive) {
      activate(panel.shown);
    }
    _panelsChanged();
  }

  @override
  void showSession(Session session) {
    final panel = panelOf(session);
    if (panel is! _Panel || session is! SessionMirror || identical(panel.shown, session)) {
      return;
    }
    final wasActive = panel.shown.active;
    panel.current = panel.columns.indexOf(session);
    if (wasActive) {
      _applyActive(session);
    }
    _panelsChanged();
  }

  /// Список или показанное изменились: рабочая область показывает другое, а
  /// ядро узнаёт, что писать в файл.
  void _panelsChanged() {
    view.showPanels();
    settingsChanged();
    notifyListeners();
  }

  /// Раскладка наборов — значениями, для настроек.
  List<PanelLayout> get panelLayout => [
    for (final panel in _panels)
      PanelLayout(
        sessions: [for (final session in panel.columns) session.id],
        current: panel.current,
        name: panel.name,
      ),
  ];

  /// Номера показанных наборов — значениями, для настроек.
  List<int> get shownPanels => [..._shown];

  /// Действия приложения: за кнопкой нижней панели и за горячей клавишей
  /// стоит одна и та же команда.
  @override
  final CommandRegistry commands;

  /// Оформление приложения. Тип уточнён до реализации: приложение владеет
  /// службой и закрывает её при выходе, остальным хватает [ThemeService].
  @override
  final ThemeController theme;

  /// Строки интерфейса: словари принесли модули, язык лежит в настройках.
  @override
  final StringsRegistry strings;

  /// Чем рисуется содержимое панелей. Без интерфейса — ничем: приложению
  /// в тесте состояния или в сценарии рисовать нечем и незачем.
  @override
  final PanelViewports viewports;

  /// Виды, которыми человек может показать каталог.
  @override
  final PanelViews panelViews;

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

  /// Правило показа имени; не дали — прежнее, без словаря.
  @override
  final FileNaming fileNaming;

  final ElevationPrompt? _elevation;

  /// Повышение прав; не дали — своё, выключенное: подставке в тестах повышать
  /// нечем и незачем.
  @override
  late final ElevationPrompt elevation =
      _elevation ?? ElevationPrompt(onAnswer: _noElevationAnswer, allowed: () => false);

  /// Отвечать некому: приложение собрано без ядра.
  static void _noAnswer(String askId, String realm, Credential? credential) {}

  static void _noElevationAnswer(String askId, bool agreed) {}

  /// Окно приложения. Без управления окном (в тестах) — заглушка.
  @override
  final WindowService window;

  /// Перетаскивание мышью; null — модуля нет.
  @override
  final DragAndDrop? dragAndDrop;

  /// Что за файл по его содержимому; null — модуля нет.
  @override
  final ContentTypes? contentTypes;

  /// Чем рисовать иконку строки; null — модуля нет.
  @override
  final FileIcons? fileIcons;

  /// Своя половина настроек: разделы модулей и то, чем экран не заведует.
  ///
  /// Свой экземпляр, а не общий с ядром: приехал рукопожатием, правится здесь
  /// и уезжает обратно сообщением (`docs/spec/client-server.md`, §9).
  final AppSettings _initialSettings;

  double _splitRatio;
  WindowGeometry? _windowGeometry;

  /// Активная панель: в ней курсор и ввод с клавиатуры.
  @override
  SessionMirror get activePanel => left.active ? left : right;

  /// Пассивная панель — приёмник операций копирования и перемещения.
  @override
  SessionMirror get passivePanel => left.active ? right : left;

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
    settingsChanged();
  }

  @override
  void activate(Session session) {
    assert(panelOf(session) != null, 'Сессия не принадлежит этому приложению');
    // Сессия из показанного набора, но не показанная, — это соседний столбец
    // комбинированного вида: щелчок по нему и делает его текущим
    // (`docs/spec/panel-sessions.md`, §2).
    final panel = panelOf(session);
    if (panel is _Panel && !identical(panel.shown, session) && session is SessionMirror) {
      panel.current = panel.columns.indexOf(session);
      view.showPanels();
      settingsChanged();
    }
    // Ввод мог быть у командной строки — тогда «сделать активной ту же самую
    // панель» означает вернуть его ей, и ранний выход ниже пропустил бы это:
    // щелчок по активной панели не выводил бы из строки.
    final released = view.releaseFocus();
    if (session.active) {
      if (released) {
        notifyListeners();
      }
      return;
    }
    _applyActive(session);
    notifyListeners();
  }

  /// Активна ровно одна сессия из всех — та, где стоит курсор.
  ///
  /// Всех, а не двух показанных: в слоте бывает несколько, и оставшийся
  /// признак у спрятанной означал бы второй курсор.
  void _applyActive(Session active) {
    for (final panel in _allSessions) {
      panel.setActive(identical(panel, active));
    }
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
    settingsChanged();
  }

  /// Запуск в два приёма: сперва ядро, потом экран.
  ///
  /// Ядро поднимает панели там, где их оставили, и здоровается — рукопожатие
  /// везёт и экранную половину настроек. Только после этого восстанавливается
  /// окно и выбирается активная панель: интерфейс подписывается на готовое, а
  /// не смотрит, как оно собирается (`docs/spec/client-server.md`, §9).
  @override
  Future<void> start() async {
    final door = link;
    if (door == null) {
      // Ядра нет вовсе (подставка в тесте состояния): поднимать нечего.
      await window.restore(_windowGeometry);
      return;
    }

    await door.call(const StartCore());
    if (await door.call(const Handshake()) case final CoreReady ready) {
      _splitRatio = ready.ui.splitRatio;
      _windowGeometry = ready.ui.window;
      _activePanel = ready.ui.activePanel;
    }

    await window.restore(_windowGeometry);
    activate(_activePanel == 1 ? right : left);
  }

  /// Какая панель была активной. Держится отдельно от самих панелей: до
  /// рукопожатия их спрашивать не о чем.
  int _activePanel = 0;

  /// Ядро приложения; null — приложение собрано без него (подставка в тесте).
  ///
  /// Держится здесь, потому что здесь же его и закрывают: ядро переживает
  /// панели и работы, а уходит вместе с приложением.
  final CoreServer? core;

  /// Дверь к ядру. Через неё уходят работы: рождаются они там, где источники
  /// (`docs/spec/client-server.md`, §5.4).
  final Link? link;

  @override
  Operation<OperationSpec, void> runOperation({String? runId, void Function(List<FileEntry> entries)? onFound}) {
    final door = link;
    if (door == null) {
      // Ядра нет вовсе: работать некому, и молчать об этом нельзя.
      throw StateError('Приложение собрано без ядра: работу заводить негде');
    }
    return RemoteOperation(door, runId: runId, onFound: onFound);
  }

  @override
  Future<ShellChannel> openShell({Session? panel, String? directory, int columns = 80, int rows = 24}) async {
    final door = link;
    if (door == null) {
      throw const FsError('', FsErrorKind.notSupported);
    }
    final reply = await door.call(
      OpenShell(panel: panel is SessionMirror ? panel.id : null, directory: directory, columns: columns, rows: rows),
    );
    if (reply is! ShellOpened) {
      // Отказ приходит бедой: клавишу нажали, и сказать, почему ничего не
      // вышло, обязательно.
      throw reply is CoreFailed ? reply.error : const FsError('', FsErrorKind.notSupported);
    }
    // Канал на разговор один, как и оболочка на место: второй означал бы
    // вторую подписку на те же байты — и ленту, в которой каждый символ
    // напечатан дважды.
    final channel = _shells[reply.runId] ??= RemoteShell(door, reply.runId);
    unawaited(channel.exitCode.then((_) => _shells.remove(reply.runId)));
    return ShellChannel(pty: channel, label: reply.label, program: reply.program, fresh: reply.fresh);
  }

  /// Открытые каналы оболочек — по имени разговора.
  final Map<String, RemoteShell> _shells = {};

  /// Содержимое объекта по его пути — мимо панелей и того, где они стоят.
  ///
  /// Разбор ведёт корень дерева, и аренду на время чтения берёт **ядро**: тот,
  /// кто читает после жеста, не обязан держать источник сам.
  @override
  Content contentAt(FileEntry entry) {
    final door = link;
    if (door == null || entry.path.isEmpty) {
      return const NoContent();
    }
    return RemoteContent(door, EntryRef.path(entry.path), length: entry.size);
  }

  /// Выключение в обратном порядке: сперва экран, потом ядро.
  ///
  /// Экран отдаёт своё — место окна, разделитель, активную панель, — а
  /// записывает настройки и закрывает источники ядро
  /// (`docs/spec/client-server.md`, §9).
  @override
  Future<void> shutdown() async {
    // Все сессии, а не только показанные: в наборе их бывает несколько, и
    // работает каждая своё (`docs/spec/panel-sessions.md`, §5).
    for (final panel in _allSessions) {
      panel.cancel();
    }
    await commands.shutdown();
    // Геометрию здесь не спрашиваем: выход происходит внутри системного
    // обработчика завершения, и обращение к плагину через платформенный канал
    // в этот момент приводит к взаимной блокировке — приложение перестаёт
    // закрываться. Сохраняется последнее известное состояние, а обновляет его
    // captureWindowGeometry.
    await save();

    // Ядро последним: до этого момента фоновые работы ещё могли читать из
    // источников, а панели — сохранять свои пути. Оно же и закроет их —
    // просьбой, а не вызовом: за портом его отсюда не достать.
    final door = link;
    if (door == null || !door.isOpen) {
      return;
    }
    await door.call(const Shutdown());
    // И закрыть дверь: иначе просьба, отправленная после ухода, ждала бы
    // ответа, которого больше некому дать
    // (`docs/spec/client-server.md`, §11, урок 2).
    await door.dispose();
  }

  @override
  int get sizeScanConcurrency => _initialSettings.sizeScanConcurrency;

  /// Настройки **этой** стороны: разделы модулей и то, чем экран не заведует.
  ///
  /// Не часть [Application]: своё модуль спрашивает разделом
  /// ([moduleSettings]), а целиком это нужно только сборке и проверкам. То,
  /// что уйдёт в файл, знает ядро — у него и своя половина, и панельная.
  AppSettings get settings => _initialSettings;

  /// Пишет в прочитанное с диска — тот же объект, что держит ядро.
  ///
  /// Панели спрашивают это значение на каждый обход, поэтому правка действует
  /// сразу, без перезапуска.
  @override
  void setSizeScanConcurrency(int value) {
    if (_initialSettings.sizeScanConcurrency == value) {
      return;
    }
    _initialSettings.sizeScanConcurrency = value;
    settingsChanged();
  }

  /// Записать настройки сейчас и дождаться записи.
  ///
  /// Ждать обязательно при выходе: процесс уходит, и отложенному таймеру
  /// сработать будет уже негде.
  Future<void> save() async {
    final door = link;
    if (door == null || !door.isOpen) {
      // Ядра нет или оно уже ушло — записывать некому и нечем.
      return;
    }
    door.tell(ChangeSettings(_ui));
    await door.call(const SaveSettings());
  }

  /// То, что держит и правит эта сторона.
  ///
  /// Разделы модулей собираются на каждую отправку: их правят окна настроек, и
  /// уехать они должны такими, какие есть сейчас.
  UiSettings get _ui => UiSettings(
    activePanel: left.active ? 0 : 1,
    splitRatio: _splitRatio,
    window: _windowGeometry,
    sizeScanConcurrency: _initialSettings.sizeScanConcurrency,
    modules: serialize(_initialSettings.modules) as Map<String, dynamic>,
    // Кто где стоит, знает только эта сторона: ядро сессии заводит, но не
    // раскладывает (`docs/spec/panel-sessions.md`, §10).
    panels: panelLayout,
    shown: shownPanels,
  );

  /// Сказать ядру, что эта половина настроек изменилась.
  ///
  /// Не ответ, а сообщение: запись отложенная, и решает её ядро — оно же
  /// видит и панели. Сравнивать снимки по эту сторону больше незачем.
  ///
  /// Наружу — потому что зовёт её и раздел модуля: «сохрани меня» приходит от
  /// окна настроек, а собрать снимок целиком может только приложение.
  void settingsChanged() => link?.tell(ChangeSettings(_ui));

  /// Спрашивает у окна его текущую геометрию и запоминает её.
  ///
  /// Вызывается на изменения окна и при уходе приложения на второй план —
  /// то есть заведомо не в момент завершения процесса.
  Future<void> captureWindowGeometry() async {
    setWindowGeometry(await window.current());
  }

  void _onWindowChanged() => unawaited(captureWindowGeometry());

  @override
  void dispose() {
    toasts.dispose();
    credentials.dispose();
    elevation.dispose();
    window.removeListener(_onWindowChanged);
    super.dispose();
  }
}

/// Набор: его столбцы и тот из них, что показан.
///
/// Столбец один, а у комбинированного вида два — дерево и список
/// (`docs/spec/panel-sessions.md`, §2).
class _Panel implements Panel {
  _Panel({required List<SessionMirror> sessions, required int current, required this.name})
    : columns = sessions,
      current = sessions.isEmpty ? 0 : current.clamp(0, sessions.length - 1);

  final List<SessionMirror> columns;

  int current;

  @override
  String name;

  SessionMirror get shown => columns[current.clamp(0, columns.length - 1)];

  @override
  Session get session => shown;

  @override
  List<Session> get sessions => List.unmodifiable(columns);
}
