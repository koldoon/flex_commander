import 'package:dicom/dicom.dart';
import 'package:logecom/logecom.dart';

import 'model/os/plugin_window_service.dart';
import 'model/os/system_open.dart';
import 'model/os/window_service.dart';
import 'model/settings/app_settings.dart';
import 'model/settings/settings_store.dart';
import 'model/tree/local/local_tree_provider.dart';
import 'model/tree/tree_provider.dart';
import 'state/app_controller.dart';
import 'state/commands/command_registry.dart';
import 'state/commands/default_commands.dart';
import 'state/panel_controller.dart';

/// Контекст приложения: что от чего зависит и в каком порядке создаётся.
///
/// Все службы приложения инстанцирует контейнер, а не вызывающий код: сборка
/// графа собрана в одном месте, а зависимости создаются лениво — при первом
/// обращении. Это важно и практически: [PluginWindowService] при создании
/// обращается к плагину окна, которого в тестах нет.
///
/// Подменяются зависимости параметрами конструктора: повторная привязка того же
/// типа в контейнере не заменяет прежнюю, а добавляется к ней.
class AppContext extends DI {
  AppContext({TreeProvider? provider, SettingsStore? store, WindowService? window}) {
    // Логгер с категорией по имени класса, который его запросил: контейнер
    // знает текущее дерево зависимостей, а предпоследний его элемент — как раз
    // потребитель логгера.
    bind<Logger>(to: (c) => Logecom.createLogger(c.plan.length > 1 ? c.plan[c.plan.length - 2] : 'App'), dynamic: true);

    bind<TreeProvider>(to: (c) => provider ?? LocalTreeProvider());
    bind<WindowService>(to: (c) => window ?? PluginWindowService());
    bind<SystemOpener>(to: (c) => openWithSystem);

    bind<SettingsStore>(
      to: (c) {
        final logger = c.get<Logger>();
        return store ??
            SettingsStore.forHome(
              c.get<TreeProvider>().homePath,
              // Испорченные настройки не должны мешать запуску, но и молчать
              // о них нельзя.
              onError: (error) => logger.warn('Settings error', error),
            );
      },
    );

    bind<PanelControllerFactory>(to: (c) => PanelControllerFactory(provider: c.get<TreeProvider>()));

    bind<CommandRegistry>(
      to: (c) => CommandRegistry(defaultCommands(opener: c.get<SystemOpener>()), defaultKeyBindings()),
    );

    bind<AppController>(
      to: (c) {
        final settings = c.get<AppSettings>();
        final panels = c.get<PanelControllerFactory>();

        // Тип зависимости контейнер берёт из места вызова, а у необязательных
        // параметров он nullable — поэтому тип указывается явно, иначе
        // контейнер стал бы искать привязку к `CommandRegistry?`.
        return AppController(
          left: panels.create(settings.left),
          right: panels.create(settings.right),
          store: c.get<SettingsStore>(),
          settings: settings,
          commands: c.get<CommandRegistry>(),
          window: c.get<WindowService>(),
        );
      },
    );
  }

  /// Собирает контекст и дочитывает то, что нельзя получить синхронно.
  ///
  /// Настройки читаются с диска, а фабрики контейнера синхронные, поэтому
  /// готовое значение связывается уже после чтения — до первого обращения
  /// к [AppController] оно всё равно никому не нужно.
  static Future<AppContext> init({TreeProvider? provider, SettingsStore? store, WindowService? window}) async {
    final context = AppContext(provider: provider, store: store, window: window);
    final settings = await context.get<SettingsStore>().load();
    context.bind<AppSettings>(to: (c) => settings);

    instance = context;
    return context;
  }

  /// Контекст приложения. Создаётся один раз в `main()`.
  static late AppContext instance;
}

/// Короткий доступ к зависимости из любого места приложения.
T inject<T>() => AppContext.instance.get<T>();
