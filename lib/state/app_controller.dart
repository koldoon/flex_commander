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
    required this.left,
    required this.right,
    this.core,
    this.link,
    required AppSettings settings,
    required this.commands,
    PanelViewports? viewports,
    List<ViewerSpec> viewers = const [],
    List<NodeInfoProvider> nodeInfoProviders = const [],
    Views? views,
    ThemeController? theme,
    ToastController? toasts,
    CredentialsController? credentials,
    ElevationPrompt? elevation,
    FileNaming? fileNaming,
    ErrorController? errors,
    WindowService? window,
    this.dragAndDrop,
  }) : _splitRatio = settings.splitRatio,
       _windowGeometry = settings.window,
       _initialSettings = settings,
       theme = theme ?? ThemeController(),
       toasts = toasts ?? ToastController(),
       // Своё, если не дали: подставке в тестах спрашивать некому и незачем.
       credentials = credentials ?? CredentialsController(onAnswer: _noAnswer),
       _elevation = elevation,
       fileNaming = fileNaming ?? const ReferenceFileNaming(),
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

  @override
  final PanelMirror left;

  @override
  final PanelMirror right;

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
    left.cancel();
    right.cancel();
    await commands.shutdown();
    // Геометрию здесь не спрашиваем: выход происходит внутри системного
    // обработчика завершения, и обращение к плагину через платформенный канал
    // в этот момент приводит к взаимной блокировке — приложение перестаёт
    // закрываться. Сохраняется последнее известное состояние, а обновляет его
    // captureWindowGeometry.
    await save();

    // Ядро последним: до этого момента фоновые работы ещё могли читать из
    // источников, а панели — сохранять свои пути. Оно же и закроет их.
    await core?.dispose();
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
    if (door == null) {
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
