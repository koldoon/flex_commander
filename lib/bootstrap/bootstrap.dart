import 'package:fc_api/fc_api.dart';

import '../settings/settings_store.dart';
import '../state/app_controller.dart';
import 'app_container.dart';
import 'app_runtime.dart';
import 'registrations.dart';

/// Сборка приложения из списка модулей.
///
/// Пять шагов подряд, и каждый следующий пользуется сделанным до него: модули
/// объявляют, что предлагают; по объявлениям собирается граф зависимостей;
/// читаются настройки; создаётся приложение; выполняются стартовые команды
/// модулей.
///
/// Порядок здесь — не украшение, а условие: контейнер нельзя собрать раньше
/// объявлений, настройки читаются до создания приложения (иначе панели встанут
/// на умолчаниях, а не там, где их оставили), а стартовые команды идут
/// последними — им нужно готовое приложение.
Future<AppRuntime> initModules(List<FcModule> modules, {AppOverrides overrides = const AppOverrides()}) async {
  // Шаг 1: модули объявляют, что они предлагают.
  final registrations = Registrations(LazyServices())..installAll(modules);

  // Шаг 2: по объявлениям собирается граф зависимостей.
  final container = AppContainer(registrations, overrides: overrides);

  // Шаг 3: настройки читаются с диска.
  //
  // Отдельным шагом, потому что чтение асинхронное, а фабрики контейнера
  // синхронные: готовое значение связывается уже после чтения.
  final settings = await container.get<SettingsStore>().load();
  container.bind<AppSettings>(to: (c) => settings);
  // С этого момента разделы настроек модулей есть где искать.
  registrations.settingsSource = settings;

  // Шаг 4: создаётся само приложение.
  final app = container.get<AppController>();
  // С этого момента командам модулей есть у кого спросить про приложение.
  if (container.context case final RuntimeContext context) {
    context.app = app;
  }
  final runtime = AppRuntime(app: app, modules: registrations.modules);

  // Шаг 5: выполняются стартовые команды модулей.
  await _runStartupCommands(container, registrations);

  return runtime;
}

/// Стартовые команды модулей — по порядку объявления.
///
/// Идут они тем же путём, что и команда, запущенная клавишей: реестр связывает
/// их с запуском и разбирает исход. Поэтому ошибка одной из них не роняет
/// запуск, а уходит в журнал — модуль темы не смог восстановить оформление,
/// приложение всё равно должно открыться.
Future<void> _runStartupCommands(AppContainer container, Registrations registrations) async {
  if (registrations.startupCommands.isEmpty) {
    return;
  }

  final registry = container.get<CommandRegistry>();
  for (final factory in registrations.startupCommands) {
    await registry.runToCompletion(factory(container.context));
  }
}
