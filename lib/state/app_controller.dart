import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import '../core/core_server.dart';
import '../link/link.dart';
import '../ui/remote_content.dart';
import '../ui/remote_shell.dart';
import '../ui/remote_operation.dart';
import '../ui/panel_mirror.dart';
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
    required PanelMirror left,
    required PanelMirror right,
    List<PanelMirror> more = const [],
    List<SlotLayout>? slots,
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
  }) : _slots = _slotsOf(left, right, more, slots),
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
    _applyActive(settings.activePanel == 1 ? this.right : this.left);
    // За закреплёнными, приехавшими из настроек, следим с первого кадра: иначе
    // закрепление переживало бы перезапуск только на вид.
    for (final slot in _slots) {
      for (final tab in slot.tabs) {
        if (tab.pinned) {
          _watchPinned(tab);
        }
      }
    }
    // Слушать панели ради записи больше незачем: их настройки — это состояние
    // сеанса, и ядро видит его раньше и точнее (`spec/client-server.md`, §9).
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

  /// Стороны, вкладки и столбцы (`docs/spec/panel-tabs.md`, §3).
  final List<_PanelSlot> _slots;

  /// Слоты по раскладке, приехавшей из настроек; сессия, которой в раскладке
  /// нет, в слот не попадает, а пустым он не бывает — там остаётся та вкладка,
  /// что стояла при запуске.
  static List<_PanelSlot> _slotsOf(
    PanelMirror left,
    PanelMirror right,
    List<PanelMirror> more,
    List<SlotLayout>? layout,
  ) {
    final byId = {
      for (final panel in [left, right, ...more]) panel.id: panel,
    };
    final slots = layout ?? UiSettings.defaultSlots;
    return [
      for (var side = 0; side < 2; side++)
        _PanelSlot(
          tabs: [
            if (side < slots.length)
              for (final tab in slots[side].tabs)
                if ([
                      for (final id in tab.panels)
                        if (byId[id] case final panel?) panel,
                    ]
                    case final columns when columns.isNotEmpty)
                  _PanelTab(columns: columns, current: tab.current, pinned: tab.pinned),
          ],
          current: side < slots.length ? slots[side].current : 0,
          fallback: side == 0 ? left : right,
        ),
    ];
  }

  @override
  PanelMirror get left => _slots[0].shown;

  @override
  PanelMirror get right => _slots[1].shown;

  /// Все сессии обеих сторон: их закрывают на выходе и о них рассказывают
  /// ядру, когда меняется раскладка.
  Iterable<PanelMirror> get _allPanels => _slots.expand((slot) => slot.panels);

  @override
  List<Panel> panelsAt(ViewportPosition side) => List.unmodifiable(_slotAt(side).shownTab.columns);

  @override
  List<PanelTab> tabsAt(ViewportPosition side) => List.unmodifiable(_slotAt(side).tabs);

  @override
  PanelTab? tabOf(Panel panel) {
    for (final slot in _slots) {
      for (final tab in slot.tabs) {
        if (tab.columns.contains(panel)) {
          return tab;
        }
      }
    }
    return null;
  }

  _PanelSlot _slotAt(ViewportPosition side) => _slots[side == ViewportPosition.right ? 1 : 0];

  /// Слот, в котором живёт эта сессия; null — сессия не наша.
  _PanelSlot? _slotOf(Panel panel) {
    for (final slot in _slots) {
      if (slot.panels.contains(panel)) {
        return slot;
      }
    }
    return null;
  }

  /// Завести сессию по образцу; null — ядра нет или оно не умеет.
  Future<PanelMirror?> _createPanel(Panel like) async {
    if (like is! PanelMirror) {
      return null;
    }
    final opened = await link?.call(OpenPanel(like.id));
    if (opened is! PanelOpened) {
      return null;
    }
    return PanelMirror(id: opened.panel, link: link!, state: opened.state, listing: opened.listing, strings: strings);
  }

  @override
  Future<Panel> openPanel(ViewportPosition side, {Panel? like, int? at}) async {
    final tab = _slotAt(side).shownTab;
    final model = like is PanelMirror ? like : tab.shown;
    final panel = await _createPanel(model);
    if (panel == null) {
      // Ядра нет или оно не умеет заводить сессии: показанная остаётся одна.
      return tab.shown;
    }
    final place = (at ?? tab.columns.length).clamp(0, tab.columns.length);
    tab.columns.insert(place, panel);
    // Показанный столбец остаётся показанным: заведение сессии не переводит
    // взгляд.
    if (place <= tab.current) {
      tab.current++;
    }
    _slotsChanged();
    return panel;
  }

  @override
  void closePanel(Panel panel) {
    final tab = tabOf(panel);
    // Последний столбец не закрывается: вкладка без панели — то же, что
    // сторона без панели.
    if (tab is! _PanelTab || tab.columns.length < 2 || panel is! PanelMirror) {
      return;
    }
    final gone = tab.columns.indexOf(panel);
    tab.columns.removeAt(gone);
    if (tab.current >= tab.columns.length) {
      tab.current = tab.columns.length - 1;
    } else if (gone < tab.current) {
      tab.current--;
    }
    final wasActive = panel.active;
    panel.close();
    if (wasActive) {
      activate(tab.shown);
    }
    _slotsChanged();
  }

  @override
  void showPanel(Panel panel) {
    final tab = tabOf(panel);
    if (tab is! _PanelTab || panel is! PanelMirror || identical(tab.shown, panel)) {
      return;
    }
    final wasActive = tab.shown.active;
    tab.current = tab.columns.indexOf(panel);
    // Показанная сессия активной стороны — она же и активная: курсор один, и
    // стоит он там, где смотрят.
    if (wasActive) {
      _applyActive(panel);
    }
    _slotsChanged();
  }

  @override
  Future<PanelTab> openTab(ViewportPosition side, {Panel? like, int? at}) async {
    final slot = _slotAt(side);
    final model = like is PanelMirror ? like : slot.shown;
    final panel = await _createPanel(model);
    if (panel == null) {
      return slot.shownTab;
    }
    final tab = _PanelTab(columns: [panel], current: 0, pinned: false);
    final place = (at ?? slot.tabs.length).clamp(0, slot.tabs.length);
    slot.tabs.insert(place, tab);
    if (place <= slot.current) {
      slot.current++;
    }
    // Заведённая вкладка и показывается: её для того и заводят.
    showTab(tab);
    return tab;
  }

  @override
  void closeTab(PanelTab tab) {
    final slot = _slotOf(tab.panel);
    // Последняя не закрывается: сторона без панели — состояние, которого в
    // модели нет вовсе.
    if (slot == null || tab is! _PanelTab || slot.tabs.length < 2) {
      return;
    }
    final gone = slot.tabs.indexOf(tab);
    slot.tabs.removeAt(gone);
    if (slot.current >= slot.tabs.length) {
      slot.current = slot.tabs.length - 1;
    } else if (gone < slot.current) {
      slot.current--;
    }
    final wasActive = tab.columns.any((panel) => panel.active);
    for (final panel in tab.columns) {
      panel.close();
    }
    if (wasActive) {
      _applyActive(slot.shown);
    }
    _slotsChanged();
  }

  @override
  void showTab(PanelTab tab) {
    final slot = _slotOf(tab.panel);
    if (slot == null || tab is! _PanelTab) {
      return;
    }
    final wasActive = slot.shown.active;
    slot.current = slot.tabs.indexOf(tab);
    if (wasActive) {
      _applyActive(slot.shown);
    }
    _slotsChanged();
  }

  @override
  void setTabPinned(PanelTab tab, bool pinned) {
    if (tab is! _PanelTab || tab.pinned == pinned) {
      return;
    }
    tab.pinned = pinned;
    _watchPinned(tab);
    _slotsChanged();
  }

  /// Следить за закреплённой вкладкой — или перестать.
  void _watchPinned(_PanelTab tab) {
    void moved() => _pinnedMoved(tab);
    // Слушатель один на вкладку: снимаем прежний в любом случае, ставим — если
    // закреплена.
    tab.shown.removeListener(tab.onMoved ?? moved);
    if (!tab.pinned) {
      tab.onMoved = null;
      tab.pinnedPath = '';
      return;
    }
    tab.pinnedPath = tab.shown.currentPath;
    tab.onMoved = moved;
    tab.shown.addListener(moved);
  }

  /// Закреплённую увели в другой каталог: новый каталог уходит в новую
  /// вкладку, а эта возвращается на свой.
  ///
  /// Не изнутри уведомления: панель рассказывает о себе, разбирая событие ядра,
  /// и просьба к ядру оттуда падает — тот же урок, что и у столбцов
  /// (`docs/spec/panel-view-combined.md`, §5).
  void _pinnedMoved(_PanelTab tab) {
    final at = tab.shown.currentPath;
    if (_closed || !tab.pinned || _returning || at.isEmpty || at == tab.pinnedPath) {
      return;
    }
    final side =
        _slots.indexWhere((slot) => slot.tabs.contains(tab)) == 1 ? ViewportPosition.right : ViewportPosition.left;
    _returning = true;
    Timer.run(() async {
      try {
        if (_closed) {
          return;
        }
        await openTab(side, like: tab.shown);
        await tab.shown.openPath(tab.pinnedPath);
      } finally {
        _returning = false;
      }
    });
  }

  /// Идёт возврат закреплённой: её собственные вести в это время не в счёт.
  bool _returning = false;

  /// Приложение уже закрыли: вести, догнавшие нас после этого, ничего не
  /// значат — отвечать на них некому.
  bool _closed = false;

  /// Раскладка изменилась: рабочая область показывает другую сессию, а ядро
  /// узнаёт, кого куда писать в файл.
  void _slotsChanged() {
    view.showPanels();
    settingsChanged();
    notifyListeners();
  }

  /// Раскладка слотов — значениями, для настроек.
  List<SlotLayout> get slotLayout => [
    for (final slot in _slots)
      SlotLayout(
        tabs: [
          for (final tab in slot.tabs)
            TabLayout(panels: [for (final panel in tab.columns) panel.id], current: tab.current, pinned: tab.pinned),
        ],
        current: slot.current,
      ),
  ];

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
  PanelMirror get activePanel => left.active ? left : right;

  /// Пассивная панель — приёмник операций копирования и перемещения.
  @override
  PanelMirror get passivePanel => left.active ? right : left;

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
  void activate(Panel panel) {
    assert(_slotOf(panel) != null, 'Панель не принадлежит этому приложению');
    // Сессия той же стороны, но не показанная, — это соседний столбец
    // комбинированного вида или другая вкладка: щелчок по ней и делает её
    // текущей (`docs/spec/panel-tabs.md`, §3).
    final slot = _slotOf(panel);
    if (slot != null && !identical(slot.shown, panel) && panel is PanelMirror) {
      final tab = tabOf(panel);
      if (tab is _PanelTab) {
        slot.current = slot.tabs.indexOf(tab);
        tab.current = tab.columns.indexOf(panel);
      }
      view.showPanels();
      settingsChanged();
    }
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
    _applyActive(panel);
    notifyListeners();
  }

  /// Активна ровно одна сессия из всех — та, где стоит курсор.
  ///
  /// Всех, а не двух показанных: в слоте бывает несколько, и оставшийся
  /// признак у спрятанной означал бы второй курсор.
  void _applyActive(Panel active) {
    for (final panel in _allPanels) {
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
  Future<ShellChannel> openShell({Panel? panel, String? directory, int columns = 80, int rows = 24}) async {
    final door = link;
    if (door == null) {
      throw const FsError('', FsErrorKind.notSupported);
    }
    final reply = await door.call(
      OpenShell(panel: panel is PanelMirror ? panel.id : null, directory: directory, columns: columns, rows: rows),
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
    // Все сессии, а не только показанные: в слоте их бывает несколько, и
    // работает каждая своё (`docs/spec/panel-slots.md`).
    for (final panel in _allPanels) {
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
    // раскладывает (`docs/spec/panel-slots.md`, §5).
    slots: slotLayout,
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
    _closed = true;
    // Слежение за закреплёнными снимается: панель ещё жива и рассказывает о
    // себе, а отвечать на это уже некому.
    for (final slot in _slots) {
      for (final tab in slot.tabs) {
        if (tab.onMoved case final moved?) {
          tab.shown.removeListener(moved);
          tab.onMoved = null;
        }
      }
    }
    toasts.dispose();
    credentials.dispose();
    elevation.dispose();
    window.removeListener(_onWindowChanged);
    super.dispose();
  }
}

/// Вкладка: её столбцы и тот из них, что показан.
///
/// Столбец один, а у комбинированного вида два — дерево и список
/// (`docs/spec/panel-tabs.md`, §3).
class _PanelTab implements PanelTab {
  _PanelTab({required this.columns, required int current, required this.pinned})
    : current = columns.isEmpty ? 0 : current.clamp(0, columns.length - 1);

  final List<PanelMirror> columns;

  int current;

  @override
  bool pinned;

  /// Слушатель, которым следят за закреплённой; null — не следят.
  VoidCallback? onMoved;

  /// Каталог, на котором закреплённая вкладка стоит.
  ///
  /// Запоминается при закреплении: уход из вкладки — это переход в другой
  /// каталог, и вернуть её надо туда, где её закрепили
  /// (`docs/spec/panel-tabs.md`, §2).
  String pinnedPath = '';

  PanelMirror get shown => columns[current];

  @override
  Panel get panel => shown;
}

/// Вкладки одной стороны и та из них, что показана.
///
/// Список живой: вкладки заводятся и закрываются на ходу, а показана всегда
/// ровно одна — её показанный столбец и стоит в области
/// (`docs/spec/panel-slots.md`, §4).
class _PanelSlot {
  _PanelSlot({required List<_PanelTab> tabs, required int current, required PanelMirror fallback})
    : tabs =
          tabs.isEmpty
              ? [
                _PanelTab(columns: [fallback], current: 0, pinned: false),
              ]
              : tabs,
      current = tabs.isEmpty ? 0 : current.clamp(0, tabs.length - 1);

  final List<_PanelTab> tabs;

  int current;

  _PanelTab get shownTab => tabs[current];

  PanelMirror get shown => shownTab.shown;

  /// Все сессии стороны — в порядке вкладок и столбцов.
  Iterable<PanelMirror> get panels => tabs.expand((tab) => tab.columns);
}
