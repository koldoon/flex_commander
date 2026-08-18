import 'package:fc_api/fc_api.dart';

import '../settings/settings_store.dart';
import '../state/app_controller.dart';
import 'app_container.dart';
import 'app_runtime.dart';
import 'registrations.dart';

/// Сборка приложения из списка модулей.
///
/// Выражена командным фреймворком не для красоты: сборка — это и есть работа
/// из нескольких шагов, где каждый следующий пользуется сделанным до него.
/// Шаги ничего не знают друг о друге: результат каждого попадает в данные
/// группы, а следующий берёт оттуда то, что ему нужно, по типу. Заодно это
/// первая проверка фреймворка на настоящей работе.
class AppBootstrapCommand implements Command {
  AppBootstrapCommand(this.modules, {this.overrides = const AppOverrides()});

  final List<FcModule> modules;

  /// Подмена служб: так тесты собирают настоящее приложение на подставках.
  final AppOverrides overrides;

  AppRuntime? _runtime;

  /// Собранное приложение. Доступно после [execute].
  AppRuntime get runtime {
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError('Приложение ещё не собрано: сначала execute');
    }
    return runtime;
  }

  @override
  Future<void> execute() async {
    final sequence =
        Commands.asSequence()
            .description('Сборка приложения')
            .add(InstallModulesCommand(modules))
            .create((data) => BuildContainerCommand(data, overrides))
            .create(LoadSettingsCommand.new)
            .create(CreateAppCommand.new)
            .create(RunStartupCommandsCommand.new)
            .build();

    await sequence.execute();

    // Собранное приложение лежит в данных последовательности — там же, где и
    // всё остальное, что шаги передавали друг другу.
    _runtime = sequence.result?.getObject<AppRuntime>();
  }

  @override
  String toString() => 'Сборка приложения';
}

/// Короткая форма для `main()` и тестов.
Future<AppRuntime> initModules(List<FcModule> modules, {AppOverrides overrides = const AppOverrides()}) async {
  final bootstrap = AppBootstrapCommand(modules, overrides: overrides);
  await bootstrap.execute();
  return bootstrap.runtime;
}

/// Шаг 1: модули объявляют, что они предлагают.
class InstallModulesCommand implements ResultCommand<Registrations> {
  InstallModulesCommand(this.modules);

  final List<FcModule> modules;

  @override
  Registrations? result;

  @override
  Future<void> execute() async {
    result = Registrations(LazyServices())..installAll(modules);
  }

  @override
  String toString() => 'Установка модулей';
}

/// Шаг 2: по объявлениям собирается граф зависимостей.
class BuildContainerCommand implements ResultCommand<AppContainer> {
  BuildContainerCommand(this.data, this.overrides);

  final CommandData data;
  final AppOverrides overrides;

  @override
  AppContainer? result;

  @override
  Future<void> execute() async {
    result = AppContainer(data.getObject<Registrations>()!, overrides: overrides);
  }

  @override
  String toString() => 'Сборка зависимостей';
}

/// Шаг 3: настройки читаются с диска.
///
/// Отдельным шагом, потому что чтение асинхронное, а фабрики контейнера
/// синхронные: готовое значение связывается уже после чтения.
class LoadSettingsCommand implements Command {
  LoadSettingsCommand(this.data);

  final CommandData data;

  @override
  Future<void> execute() async {
    final container = data.getObject<AppContainer>()!;
    final settings = await container.get<SettingsStore>().load();
    container.bind<AppSettings>(to: (c) => settings);
  }

  @override
  String toString() => 'Чтение настроек';
}

/// Шаг 4: создаётся само приложение.
class CreateAppCommand implements ResultCommand<AppRuntime> {
  CreateAppCommand(this.data);

  final CommandData data;

  @override
  AppRuntime? result;

  @override
  Future<void> execute() async {
    final container = data.getObject<AppContainer>()!;
    final registrations = data.getObject<Registrations>()!;
    final app = container.get<AppController>();

    // С этого момента командам модулей есть у кого спросить про приложение.
    if (container.context case final RuntimeContext context) {
      context.app = app;
    }

    result = AppRuntime(app: app, modules: registrations.modules);
  }

  @override
  String toString() => 'Создание приложения';
}

/// Шаг 5: выполняются стартовые команды модулей.
///
/// Ошибка одной из них не роняет запуск: модуль темы не смог восстановить
/// оформление — приложение всё равно должно открыться.
class RunStartupCommandsCommand implements Command {
  RunStartupCommandsCommand(this.data);

  final CommandData data;

  @override
  Future<void> execute() async {
    final container = data.getObject<AppContainer>()!;
    final registrations = data.getObject<Registrations>()!;
    if (registrations.startupCommands.isEmpty) {
      return;
    }

    final group = Commands.asSequence()
        .description('Стартовые команды')
        .skipErrors()
        .lifecycle(container.get<CommandRegistry>());

    for (final factory in registrations.startupCommands) {
      group.create((data) => factory(container.context));
    }

    await group.execute();
  }

  @override
  String toString() => 'Стартовые команды';
}
