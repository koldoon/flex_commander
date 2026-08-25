import 'package:dicom/dicom.dart';
import 'package:fc_api/fc_api.dart';
import 'package:logecom/logecom.dart';

import '../settings/settings_store.dart';
import '../state/app_controller.dart';
import '../state/panel_controller.dart';
import '../state/panel_viewport_registry.dart';
import '../state/view_registry.dart';
import '../state/theme_controller.dart';
import '../state/credentials_controller.dart';
import '../state/error_controller.dart';
import '../state/toast_controller.dart';
import 'app_runtime.dart';
import 'registrations.dart';

/// Граф зависимостей приложения, собранный по объявлениям модулей.
///
/// Здесь нет ни одного имени конкретной возможности: что будет корневым
/// источником, какие есть команды и чем открывается zip — приходит из
/// [Registrations]. Раньше всё это было записано прямо в контейнере, и добавить
/// возможность значило поправить ядро.
class AppContainer extends DI {
  AppContainer(this.registrations, {this.overrides = const AppOverrides(), FcContext? context}) {
    _context = context ?? RuntimeContext(registrations.services);

    // Логгер с категорией по имени класса, который его запросил: контейнер
    // знает текущее дерево зависимостей, а предпоследний его элемент — как раз
    // потребитель логгера.
    bind<Logger>(to: (c) => Logecom.createLogger(c.plan.length > 1 ? c.plan[c.plan.length - 2] : 'App'), dynamic: true);

    _bindServices();
    _bindTree();
    _bindCommands();
    _bindSettings();
    _bindApp();

    registrations.services.bindTo(this);
  }

  final Registrations registrations;
  final AppOverrides overrides;
  late final FcContext _context;

  /// Окружение, в котором создаются команды модулей.
  FcContext get context => _context;

  void _bindServices() {
    // Подмена важнее объявления модуля: тесты собирают настоящее приложение,
    // но с подставным окном и хранилищем.
    final overridden = <Type>{if (overrides.window != null) WindowService, if (overrides.store != null) SettingsStore};

    for (final entry in registrations.serviceBindings.entries) {
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

  void _bindTree() {
    final root = registrations.rootProviderFactory;
    final provider = overrides.provider;
    if (root == null && provider == null) {
      throw StateError('Ни один модуль не объявил корневой источник дерева');
    }

    bind<TreeProvider>(to: (c) => provider ?? root!(registrations.services));

    bind<ProviderRegistry>(
      to: (c) {
        final registry = ProviderRegistry(root: c.get<TreeProvider>());
        for (final declared in registrations.providers) {
          registry.register(declared.scheme, declared.factory, extensions: declared.extensions);
        }
        for (final declared in registrations.addresses) {
          registry.registerAddress(declared.scheme, declared.factory);
        }
        return registry;
      },
    );
  }

  void _bindCommands() {
    bind<CommandRegistry>(
      to: (c) {
        final logger = c.get<Logger>();
        return CommandRegistry(
          // Фабрика модуля просит окружение, реестру нужна фабрика без
          // аргументов: окружение подставляется здесь, при сборке.
          [for (final factory in registrations.commands) () => factory(_context)],
          registrations.bindings,
          // У команды с окном ошибка остаётся в окне. У команды без окна
          // показать её негде — до появления общего места для фоновых работ
          // она хотя бы попадает в журнал, а не пропадает совсем.
          (error, command) => logger.error('Command failed: $command', error),
        );
      },
    );

    if (registrations.themes.isEmpty) {
      throw StateError('Ни один модуль не объявил оформление');
    }
    bind<ThemeController>(to: (c) => ThemeController(registrations.themes));

    bind<PanelViewports>(
      to: (c) {
        // Таблица файлов — вид по умолчанию: её ядро умеет всегда, остальное
        // приносят модули.
        final viewports = PanelViewportRegistry();
        for (final entry in registrations.viewports.entries) {
          viewports.register(entry.key, entry.value);
        }
        return viewports;
      },
    );

    bind<Views>(to: (c) => ViewRegistry(registrations.views));
  }

  void _bindSettings() {
    bind<SettingsStore>(
      to: (c) {
        final logger = c.get<Logger>();
        return overrides.store ??
            SettingsStore.forHome(
              c.get<TreeProvider>().homePath,
              // Испорченные настройки не должны мешать запуску, но и молчать
              // о них нельзя.
              onError: (error) => logger.warn('Settings error', error),
            );
      },
    );
  }

  void _bindApp() {
    bind<PanelControllerFactory>(
      to:
          (c) => PanelControllerFactory(
            registry: c.get<ProviderRegistry>(),
            editor: c.get<TreeEditor>(),
            sizeScanConcurrency: c.get<AppSettings>().sizeScanConcurrency,
          ),
    );

    // Наружу приложение отдаётся интерфейсом: команды и всё, что пишется
    // против API, не должны видеть реализацию.
    // Секреты — одна служба на приложение: спрошенный пароль должен быть
    // виден и той панели, которая спросила, и той, что откроет тот же архив.
    bind<CredentialsController>(to: (c) => CredentialsController());

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
        final settings = c.get<AppSettings>();
        final panels = c.get<PanelControllerFactory>();

        // Правая панель может стоять на своём источнике: так тест проверяет
        // перенос между провайдерами, не проходя весь путь через монтирование.
        final rightProvider = overrides.rightProvider;
        final rightPanels =
            rightProvider == null
                ? panels
                : PanelControllerFactory(
                  registry: ProviderRegistry(root: rightProvider),
                  editor: c.get<TreeEditor>(),
                  sizeScanConcurrency: settings.sizeScanConcurrency,
                );

        return AppController(
          left: panels.create(settings.left),
          right: rightPanels.create(settings.right),
          store: c.get<SettingsStore>(),
          settings: settings,
          commands: c.get<CommandRegistry>(),
          providers: c.get<ProviderRegistry>(),
          theme: c.get<ThemeController>(),
          viewports: c.get<PanelViewports>(),
          window: c.get<WindowService>(),
          saveDelay: overrides.saveDelay ?? const Duration(seconds: 1),
          toasts: ToastController(duration: overrides.toastDuration ?? ToastController.defaultDuration),
          credentials: c.get<CredentialsController>(),
          errors: c.get<ErrorController>(),
        );
      },
    );
  }
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
