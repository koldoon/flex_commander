import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import '../settings/settings_store.dart';
import '../state/app_controller.dart';

/// Подмена служб при сборке: провайдер, хранилище настроек, окно.
///
/// Не «настройки приложения», а именно подмена: так тесты собирают настоящее
/// приложение на подставных службах, ничего не зная о его внутреннем графе.
class AppOverrides {
  const AppOverrides({this.provider, this.rightProvider, this.store, this.window, this.saveDelay, this.toastDuration});

  final TreeProvider? provider;

  /// Источник правой панели, если он должен отличаться от левой.
  ///
  /// В настоящем приложении панели начинают с одного корня и расходятся, войдя
  /// в архив или подключившись к серверу. Тесту переноса это долгий путь:
  /// проще дать панелям разные источники сразу.
  final TreeProvider? rightProvider;
  final SettingsStore? store;
  final WindowService? window;

  /// Через сколько после изменения настройки уходят в хранилище.
  ///
  /// В тестах короче: отложенная запись, оставшаяся висеть таймером, роняет
  /// виджет-тест — и правильно делает, в настоящем приложении такой таймер
  /// пережил бы окно.
  final Duration? saveDelay;

  /// Сколько висит всплывающее сообщение. В тестах короче — по той же причине,
  /// что и [saveDelay]: таймер не должен пережить тест.
  final Duration? toastDuration;
}

/// Собранное приложение.
///
/// То, что нужно `runApp` и тестам: само приложение, его службы и способ всё
/// это закрыть.
class AppRuntime {
  AppRuntime({required this.app, required List<FcModule> modules, FcServices? services})
    : _modules = modules,
      _services = services;

  final AppController app;
  final List<FcModule> _modules;
  final FcServices? _services;

  /// Служба приложения — та же, что видят фабрики модулей.
  ///
  /// Нужна тестам: приложение отдаёт наружу панели, команды и оформление, а
  /// проверить иногда надо и то, что живёт службой, — например разделы окна
  /// настроек. Бросает, если приложение собрано без графа зависимостей.
  T resolve<T>() {
    final services = _services;
    if (services == null) {
      throw StateError('Приложение собрано без служб: спрашивать нечего');
    }
    return services.resolve<T>();
  }

  /// Модули в порядке установки.
  List<FcModule> get modules => List.unmodifiable(_modules);

  CommandService get commands => app.commands;

  /// Реестр провайдеров: чем открываются архивы и адреса, и что открыто сейчас.
  ProviderRegistry? get providers => app.providers;

  ThemeService get theme => app.theme;

  /// Закрывает приложение: сперва модули, потом само приложение.
  ///
  /// Порядок важен: модуль может держать соединение или временный файл, и
  /// закрывать их нужно, пока приложение ещё живо.
  Future<void> dispose() async {
    for (final module in _modules) {
      if (module is FcModuleLifecycle) {
        await (module as FcModuleLifecycle).dispose();
      }
    }
    await app.shutdown();
    app.dispose();
  }
}
