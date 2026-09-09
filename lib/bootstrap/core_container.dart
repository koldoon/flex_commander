import 'package:dicom/dicom.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:logecom/logecom.dart';

import '../core/core_server.dart';
import '../core/elevated_writes.dart';
import '../core/listing_cache.dart';
import '../core/panel_session.dart';
import '../core/secrets_hub.dart';
import '../core/settings_hub.dart';
import '../core/settings_store.dart';
import '../state/compound_file_naming.dart';
import '../state/shell_settings.dart';
import 'app_runtime.dart';
import 'language.dart';
import 'backend_registrations.dart';
import 'registrations.dart';

/// Граф зависимостей **ядра**, собранный по объявлениям его модулей.
///
/// Экрана здесь нет и быть не может: ни команды, ни темы, ни виджета в этом
/// графе не встретится — их типов эта сторона попросту не видит. Это и есть
/// третий ответ на «где граница», после разреза пакетов и двух списков модулей
/// (`docs/spec/client-server.md`, §3).
class CoreContainer extends DI {
  CoreContainer(this.backend, this.services, {this.overrides = const AppOverrides(), this.settingsPath = ''}) {
    // Логгер с категорией по имени класса, который его запросил: контейнер
    // знает текущее дерево зависимостей, а предпоследний его элемент — как раз
    // потребитель логгера.
    bind<Logger>(
      to: (c) => Logecom.createLogger(c.plan.length > 1 ? c.plan[c.plan.length - 2] : 'Core'),
      dynamic: true,
    );

    _bindServices();
    _bindTree();
    _bindSettings();
    _bindCore();

    services.bindTo(this);
  }

  /// Что объявили ядровые половины модулей.
  final BackendRegistrations backend;

  /// Службы ядра — те, что видят фабрики его модулей.
  final LazyServices services;

  final AppOverrides overrides;

  /// Куда писать настройки; пусто — туда, куда пишет приложение.
  ///
  /// Путь, а не хранилище: подменить объект можно только по эту сторону порта,
  /// а путь уезжает в изолят как есть.
  final String settingsPath;

  void _bindServices() {
    // Подмена важнее объявления модуля: тесты собирают настоящее приложение,
    // но с подставным хранилищем.
    final overridden = <Type>{if (overrides.store != null) SettingsStore};

    for (final entry in backend.serviceBindings.entries) {
      if (overridden.contains(entry.key)) {
        continue;
      }
      entry.value(this);
    }
  }

  void _bindTree() {
    final root = backend.rootProviderFactory;
    final provider = overrides.provider;
    if (root == null && provider == null) {
      throw StateError('Ни один модуль не объявил корневой источник дерева');
    }

    bind<TreeProvider>(to: (c) => provider ?? root!(services));

    bind<ProviderRegistry>(
      to: (c) {
        final registry = ProviderRegistry(root: c.get<TreeProvider>());
        for (final declared in backend.providers) {
          registry.register(declared.scheme, declared.factory, extensions: declared.extensions);
        }
        for (final declared in backend.addresses) {
          registry.registerAddress(declared.scheme, declared.factory);
        }
        return registry;
      },
    );
  }

  void _bindSettings() {
    bind<SettingsStore>(
      to: (c) {
        final logger = c.get<Logger>();
        if (settingsPath.isNotEmpty) {
          return SettingsStore(filePath: settingsPath, fallbackPath: c.get<TreeProvider>().homePath);
        }
        return overrides.store ??
            SettingsStore.forHome(
              c.get<TreeProvider>().homePath,
              // Испорченные настройки не должны мешать запуску, но и молчать
              // о них нельзя.
              onError: (error) => logger.warn('Settings error', error),
            );
      },
    );

    // Словарь составных расширений — правило **показа**, но применяет его
    // сортировка, а она здесь: имя делится на имя и расширение там же, где
    // список и складывается.
    //
    // Раздел берётся **сразу**, а не при первом обращении: он попадает в
    // снимок настроек, по которому решается, нужна ли запись. Появись он
    // позже — первый же снимок разошёлся бы со вторым, и приложение
    // планировало бы запись на ровном месте. А значения спрашиваются каждый
    // раз: правку словаря в окне настроек должен показать следующий же список.
    bind<FileNaming>(
      to: (c) {
        final shell = c.get<AppSettings>().modules.scope('fc.shell').section(ShellSettings.new);
        return CompoundFileNaming(
          compound: () => shell.compoundExtensions,
          useBuiltin: () => shell.useBuiltinExtensions,
        );
      },
    );
  }

  void _bindCore() {
    // Строки ядра: вехи работы, которые видно в строке состояния панели.
    // Словари свои — те, что объявила ядровая половина модуля, — а язык тот же,
    // и берётся он из тех же настроек (`docs/spec/localization.md`, §5).
    bind<Strings>(
      to: (c) {
        backend.translations.languageSource =
            () =>
                overrides.language ??
                languageOf(c.get<AppSettings>().modules.scope('fc.shell').section(ShellSettings.new).language);
        return backend.translations;
      },
    );

    bind<SecretsHub>(to: (c) => SecretsHub());

    bind<ElevatedWrites>(
      to: (c) {
        final secrets = c.get<SecretsHub>();
        return CoreElevation(
          credentials: secrets,
          ask: secrets.askElevation,
          // Настройка спрашивается лениво: раздел читается с диска позже, чем
          // собирается граф.
          allowed: () => c.get<AppSettings>().modules.scope('fc.shell').section(ShellSettings.new).allowElevatedWrites,
          strings: c.get<Strings>(),
        );
      },
    );
    bind<Credentials>(to: (c) => c.get<SecretsHub>());

    // Списки уже прочитанных каталогов — один на приложение: каталог,
    // прочитанный левой панелью, достаётся правой даром
    // (`docs/spec/listing-cache.md`).
    bind<ListingCache>(
      to: (c) {
        // Раздел спрашивается лениво и каждый раз — как и у повышения прав:
        // с диска он читается позже, чем собирается граф, а правку в окне
        // настроек должен показать следующий же переход.
        ShellSettings shell() => c.get<AppSettings>().modules.scope('fc.shell').section(ShellSettings.new);
        final cache = ListingCache(
          enabled: () => shell().listingCache,
          limit: () => shell().listingCacheLimit,
          ttl: () => Duration(seconds: shell().listingCacheTtl),
        );
        // Закрыли архив — записи о его каталогах стали ссылками на мертвеца.
        // Подписка здесь, а не в кеше: аренды он не берёт нарочно, иначе не
        // дал бы закрыться архиву, в который заглянули один раз.
        c.get<ProviderRegistry>().onProviderClosed(cache.forgetProvider);
        return cache;
      },
    );

    bind<PanelSessionFactory>(
      to:
          (c) => PanelSessionFactory(
            registry: c.get<ProviderRegistry>(),
            editor: c.get<TreeEditor>(),
            sizeScanConcurrency: () => c.get<AppSettings>().sizeScanConcurrency,
            naming: c.get<FileNaming>(),
            cache: c.get<ListingCache>(),
            strings: c.get<Strings>(),
          ),
    );

    bind<CoreServer>(
      to: (c) {
        final settings = c.get<AppSettings>();
        final panels = c.get<PanelSessionFactory>();

        // Правая панель может стоять на своём источнике: так тест проверяет
        // перенос между провайдерами, не проходя весь путь через монтирование.
        final rightProvider = overrides.rightProvider;
        final rightPanels =
            rightProvider == null
                ? panels
                : PanelSessionFactory(
                  registry: ProviderRegistry(root: rightProvider),
                  editor: c.get<TreeEditor>(),
                  sizeScanConcurrency: () => settings.sizeScanConcurrency,
                  // Кеш тот же: он и заведён общим. Одинаковые пути в двух
                  // источниках он не путает — список отдаётся только своему
                  // провайдеру.
                  cache: c.get<ListingCache>(),
                );

        // Сессии заводятся по файлу — по порядку наборов и столбцов в них;
        // личности выдаются тем же порядком (`docs/spec/panel-sessions.md`, §4).
        // Подставной правый источник достаётся набору, показанному справа.
        final rightShown = settings.groupAt(1);
        final sessions = <PanelId, PanelSession>{};
        final layout = <PanelLayout>[];

        for (final group in settings.panels) {
          final ids = <PanelId>[];
          for (final session in group.sessions) {
            final id = PanelId(sessions.length);
            sessions[id] = (identical(group, rightShown) ? rightPanels : panels).create(session);
            ids.add(id);
          }
          layout.add(PanelLayout(sessions: ids, current: group.current.clamp(0, ids.length - 1), name: group.name));
        }

        return CoreServer(
          sessions: sessions,
          // Заводится новая тем же, чем и первая: сторон ядро не знает, а
          // подставной источник правой — приём проверок, а не правило.
          createSession: panels.create,
          registry: c.get<ProviderRegistry>(),
          editor: c.get<TreeEditor>(),
          services: services,
          operations: backend.operations,
          settings: SettingsHub(
            store: c.get<SettingsStore>(),
            stored: settings,
            // Карта заведённых — только пока ядро собирается: собравшись, оно
            // подменит её собой (`SettingsHub.bindPanels`).
            panelSettings: (panel) => sessions[panel]?.settings,
            panels: layout,
            shown: settings.shown,
            saveDelay: overrides.saveDelay ?? SettingsHub.defaultSaveDelay,
          ),
          secrets: c.get<SecretsHub>(),
        );
      },
    );
  }
}
