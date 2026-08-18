import 'package:fc_api/fc_api.dart';

import '../settings/settings_store.dart';
import '../state/app_controller.dart';

/// Подмена служб при сборке: провайдер, хранилище настроек, окно.
///
/// Не «настройки приложения», а именно подмена: так тесты собирают настоящее
/// приложение на подставных службах, ничего не зная о его внутреннем графе.
class AppOverrides {
  const AppOverrides({this.provider, this.store, this.window, this.saveDelay});

  final TreeProvider? provider;
  final SettingsStore? store;
  final WindowService? window;

  /// Через сколько после изменения настройки уходят в хранилище.
  ///
  /// В тестах короче: отложенная запись, оставшаяся висеть таймером, роняет
  /// виджет-тест — и правильно делает, в настоящем приложении такой таймер
  /// пережил бы окно.
  final Duration? saveDelay;
}

/// Собранное приложение.
///
/// То, что нужно `runApp` и тестам: само приложение, его службы и способ всё
/// это закрыть.
class AppRuntime {
  AppRuntime({required this.app, required List<FcModule> modules}) : _modules = modules;

  final AppController app;
  final List<FcModule> _modules;

  /// Модули в порядке установки.
  List<FcModule> get modules => List.unmodifiable(_modules);

  CommandService get commands => app.commands;

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
