import 'package:dicom/dicom.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:logecom/logecom.dart';

import '../core/core_server.dart';
import '../link/link.dart';
import '../state/app_controller.dart';
import '../state/compound_file_naming.dart';
import '../state/shell_settings.dart';
import '../state/error_controller.dart';
import '../state/panel_viewport_registry.dart';
import '../state/theme_controller.dart';
import '../state/toast_controller.dart';
import '../state/view_registry.dart';
import '../ui/credentials_prompt.dart';
import '../ui/elevation_prompt.dart';
import '../ui/panel_mirror.dart';
import '../ui/secrets_client.dart';
import 'app_runtime.dart';
import 'frontend_registrations.dart';
import 'registrations.dart';

/// Граф зависимостей **интерфейса**, собранный по объявлениям его модулей.
///
/// Дерева здесь нет и быть не может: ни провайдера, ни узла, ни аренды в этом
/// графе не встретится — их типов эта сторона не видит вовсе. С ядром он
/// связан ровно одним: линком (`docs/spec/client-server.md`, §3).
class UiContainer extends DI {
  UiContainer(
    this.frontend,
    this.services, {
    required this.link,
    required CoreReady ready,
    this.core,
    this.overrides = const AppOverrides(),
    FcContext? context,
  }) : _settings = settingsFrom(ready.ui),
       _handshake = ready {
    _context = context ?? RuntimeContext(services);

    bind<Logger>(to: (c) => Logecom.createLogger(c.plan.length > 1 ? c.plan[c.plan.length - 2] : 'App'), dynamic: true);
    bind<AppSettings>(to: (c) => _settings);

    // Правило показа: как имя делится на имя и расширение. Своё, а не общее с
    // ядром: значения те же (раздел один), а экземпляр у каждой стороны свой —
    // так и должно быть, они не видят друг друга.
    bind<FileNaming>(
      to: (c) {
        final shell = _settings.modules.scope('fc.shell').section(ShellSettings.new);
        return CompoundFileNaming(
          compound: () => shell.compoundExtensions,
          useBuiltin: () => shell.useBuiltinExtensions,
        );
      },
    );

    _bindServices();
    _bindCommands();
    _bindApp();

    services.bindTo(this);
  }

  /// Настройки этой стороны — те, что приехали рукопожатием.
  AppSettings get settings => _settings;

  /// Что объявили экранные половины модулей.
  final FrontendRegistrations frontend;

  /// Службы интерфейса — те, что видят фабрики его модулей.
  final LazyServices services;

  /// Дверь к ядру: всё, что связывает эту сторону с той.
  final Link link;

  /// Ядро — только чтобы закрыть его вместе с приложением.
  ///
  /// Держит его приложение, потому что там же и закрывает: ядро переживает
  /// панели и работы, а уходит вместе с ним.
  final CoreServer? core;

  final AppOverrides overrides;

  /// Своя половина настроек — та, что приехала рукопожатием.
  ///
  /// Свой экземпляр, а не общий с ядром: с изолятом общего объекта не бывает
  /// вовсе, а до него он был последней ниточкой между сторонами
  /// (`docs/spec/client-server.md`, §9).
  final AppSettings _settings;

  /// Настройки этой стороны из того, что приехало.
  ///
  /// Панельные разделы сюда не попадают: их держит ядро, и экрану они не
  /// нужны — панель рассказывает о себе состоянием.
  static AppSettings settingsFrom(UiSettings ui) {
    final settings = AppSettings(
      activePanel: ui.activePanel,
      splitRatio: ui.splitRatio,
      sizeScanConcurrency: ui.sizeScanConcurrency,
      window: ui.window,
    );
    settings.modules.fromMap(ui.modules);
    return settings;
  }

  /// Рукопожатие: начальный снимок панелей и экранная половина настроек.
  ///
  /// Сделано **до** сборки интерфейса и передано сюда готовым: спрашивать его
  /// из фабрики значило бы сделать сборку асинхронной, а первый кадр — пустым.
  final CoreReady _handshake;

  late final FcContext _context;

  /// Окружение, в котором создаются команды модулей.
  FcContext get context => _context;

  void _bindServices() {
    // Подмена важнее объявления модуля: тесты собирают настоящее приложение,
    // но с подставным окном.
    final overridden = <Type>{if (overrides.window != null) WindowService};

    for (final entry in frontend.serviceBindings.entries) {
      if (overridden.contains(entry.key)) {
        continue;
      }
      entry.value(this);
    }

    final window = overrides.window;
    if (window != null) {
      bind<WindowService>(to: (c) => window);
    }
  }

  void _bindCommands() {
    bind<CommandRegistry>(
      to: (c) {
        final logger = c.get<Logger>();
        return CommandRegistry(
          // Фабрика модуля просит окружение, реестру нужна фабрика без
          // аргументов: окружение подставляется здесь, при сборке.
          [for (final factory in frontend.commands) () => factory(_context)],
          frontend.bindings,
          // У команды с окном ошибка остаётся в окне. У команды без окна
          // показать её негде — до появления общего места для фоновых работ
          // она хотя бы попадает в журнал, а не пропадает совсем.
          (error, command) => logger.error('Command failed: $command', error),
          frontend.commandOwners,
        );
      },
    );

    if (frontend.themes.isEmpty) {
      throw StateError('Ни один модуль не объявил оформление');
    }
    bind<ThemeController>(to: (c) => ThemeController(frontend.themes));

    bind<PanelViewports>(
      to: (c) {
        // Таблица файлов — вид по умолчанию: её ядро умеет всегда, остальное
        // приносят модули.
        final viewports = PanelViewportRegistry();
        for (final entry in frontend.viewports.entries) {
          viewports.register(entry.key, entry.value);
        }
        return viewports;
      },
    );

    bind<Views>(to: (c) => ViewRegistry(frontend.views));

    // Разделы окна настроек: собраны при объявлении, строятся при открытии.
    bind<SettingsCatalog>(to: (c) => _Catalog(frontend.settingsPages));
  }

  void _bindApp() {
    // Вопросы ядра: показать и ответить. Слушатель заводится сразу — вопрос
    // может прийти с первого же обращения к источнику.
    bind<CredentialsController>(
      to:
          (c) => CredentialsController(
            onAnswer: (askId, realm, credential) => link.tell(AnswerCredential(askId, credential, realm: realm)),
          ),
    );
    bind<ElevationPrompt>(
      to:
          (c) => ElevationPrompt(
            onAnswer: (askId, agreed) => link.tell(AnswerElevation(askId, agreed: agreed)),
            allowed: () => _settings.modules.scope('fc.shell').section(ShellSettings.new).allowElevatedWrites,
          ),
    );
    bind<SecretsClient>(
      to:
          (c) => SecretsClient(
            link: link,
            credentials: c.get<CredentialsController>(),
            elevation: c.get<ElevationPrompt>(),
          ),
    );

    // Сборщик непойманных ошибок — одна служба на приложение: ловушки ставятся
    // до первого кадра, а показывать пойманное будет окно, когда появится.
    bind<ErrorController>(
      to:
          (c) => ErrorController(
            clipboard: c.get<ClipboardService>(),
            onLog:
                (report) =>
                    Logecom.createLogger('App').error(report.context ?? 'Unhandled', [report.error, report.stack]),
          ),
    );
    bind<Errors>(to: (c) => c.get<ErrorController>());

    bind<Application>(to: (c) => c.get<AppController>());

    bind<AppController>(
      to: (c) {
        // Слушатель вопросов встаёт до приложения: первый же поход в источник
        // может спросить пароль.
        c.get<SecretsClient>();

        PanelMirror mirror(PanelId id, PanelState state, PanelListing listing) =>
            PanelMirror(id: id, link: link, state: state, listing: listing);

        final ready = _handshake;

        return AppController(
          left: mirror(PanelId.left, ready.states[PanelId.left]!, ready.listings[PanelId.left]!),
          right: mirror(PanelId.right, ready.states[PanelId.right]!, ready.listings[PanelId.right]!),
          core: core,
          link: link,
          settings: _settings,
          commands: c.get<CommandRegistry>(),
          theme: c.get<ThemeController>(),
          viewports: c.get<PanelViewports>(),
          // Списком, а не службой: складывать и упорядочивать — вся работа
          // оболочки с просмотрщиками. Кто возьмётся за файл, спрашивает она.
          viewers: frontend.viewers,
          // Фабрики зовутся здесь, когда приложение уже собрано: провайдеру
          // сведений может понадобиться служба, а во время объявления её ещё
          // нет.
          nodeInfoProviders: [for (final factory in frontend.nodeInfoFactories) factory(_context)],
          views: c.get<Views>(),
          window: c.get<WindowService>(),
          // Необязательная: нет модуля перетаскивания — панели просто не умеют
          // принимать файлы мышью, и ничего больше не меняется.
          //
          // Спрашивается по объявлениям, а не у контейнера: мы **внутри** его
          // фабрики, и обращение к нему отсюда рушит разбор зависимостей.
          dragAndDrop: frontend.serviceBindings.containsKey(DragAndDrop) ? c.get<DragAndDrop>() : null,
          // Так же необязательна: нет модуля типов — показ обходится тем, что
          // знает по имени.
          contentTypes: frontend.serviceBindings.containsKey(ContentTypes) ? c.get<ContentTypes>() : null,
          fileIcons: frontend.serviceBindings.containsKey(FileIcons) ? c.get<FileIcons>() : null,
          toasts: ToastController(duration: overrides.toastDuration ?? ToastController.defaultDuration),
          credentials: c.get<CredentialsController>(),
          fileNaming: c.get<FileNaming>(),
          elevation: c.get<ElevationPrompt>(),
          errors: c.get<ErrorController>(),
        );
      },
    );
  }
}

/// Разделы настроек — реализация [SettingsCatalog].
///
/// Отдельным классом, а не списком наружу: окно спрашивает службу по типу и о
/// сборке приложения не знает.
class _Catalog implements SettingsCatalog {
  const _Catalog(this.pages);

  @override
  final List<SettingsPage> pages;
}

/// Окружение команд модуля: службы плюс само приложение.
///
/// Приложения на момент сборки ещё нет, поэтому оно проставляется потом.
/// Тип при этом честный: фабрика службы получает [FcServices] и до приложения
/// добраться не может в принципе.
class RuntimeContext implements FcContext {
  RuntimeContext(this._services);

  final FcServices _services;
  Application? _app;

  /// Только для сборки.
  set app(Application value) => _app = value;

  @override
  Application get app {
    final app = _app;
    if (app == null) {
      throw StateError('Приложение ещё не собрано: команду создают уже после сборки');
    }
    return app;
  }

  @override
  T resolve<T>() => _services.resolve<T>();

  @override
  List<T> resolveAll<T>() => _services.resolveAll<T>();
}
