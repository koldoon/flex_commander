import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'package:flutter/services.dart';

import '../core/core_main.dart';
import '../core/core_server.dart';
import '../core/settings_store.dart';
import '../link/isolate_link.dart';
import '../link/link.dart';
import '../link/loopback_link.dart';
import '../state/app_controller.dart';
import 'app_runtime.dart';
import 'backend_registrations.dart';
import 'core_container.dart';
import 'frontend_registrations.dart';
import 'registrations.dart';
import 'ui_container.dart';

/// Сборка приложения из двух списков модулей — **в два приёма**.
///
/// Сперва целиком поднимается ядро: его модули, настройки с диска, корневой
/// источник, сеансы панелей. Потом — рукопожатие, и только по нему собирается
/// интерфейс: его модули, команды, темы, окно. Интерфейс подписывается на
/// готовое, а не смотрит, как оно собирается
/// (`docs/spec/client-server.md`, §9).
///
/// Порядок здесь — не украшение, а условие. Настройки читаются до сеансов
/// (иначе панели встанут на умолчаниях, а не там, где их оставили);
/// рукопожатие — до интерфейса (иначе первый кадр окажется пустым); стартовые
/// команды — последними, им нужно готовое приложение.
///
/// Контейнера два, и это третий ответ на «где граница»: в графе ядра нет ни
/// одной экранной службы, в графе интерфейса — ни одного провайдера. Связывает
/// их ровно одно — линк.
Future<AppRuntime> initModules(
  List<FcBackendModule> backend,
  List<FcFrontendModule> frontend, {
  AppOverrides overrides = const AppOverrides(),
}) async {
  // Шаг 1: ядро объявляет, что предлагает, и собирается.
  final coreServices = LazyServices();
  final backendRegistrations = BackendRegistrations(coreServices)..installAll(backend);
  final coreContainer = CoreContainer(backendRegistrations, coreServices, overrides: overrides);

  // Шаг 2: настройки читаются с диска — файл принадлежит ядру.
  //
  // Отдельным шагом, потому что чтение асинхронное, а фабрики контейнера
  // синхронные: готовое значение связывается уже после чтения.
  final settings = await coreContainer.get<SettingsStore>().load();
  coreContainer.bind<AppSettings>(to: (c) => settings);
  backendRegistrations.settingsSource = settings;

  // Шаг 3: ядро поднято — открывается дверь.
  final core = coreContainer.get<CoreServer>();
  final link = LoopbackLink(core);

  // Шаг 4: рукопожатие. До него дверь закрыта: тот, кто спросил раньше, ждёт.
  final ready = await link.call(const Handshake()) as CoreReady;
  // Шаг 5: интерфейс объявляет своё и собирается — уже по готовому снимку.
  return _frontend(frontend, link: link, ready: ready, core: core, overrides: overrides, backend: backendRegistrations);
}

/// Сборка интерфейса — общая для обеих дверей.
///
/// Тем и хороша: разница между петлёй и портом кончается здесь, и всё, что
/// после, о ней уже не знает.
Future<AppRuntime> _frontend(
  List<FcFrontendModule> frontend, {
  required Link link,
  required CoreReady ready,
  CoreServer? core,
  AppOverrides overrides = const AppOverrides(),
  BackendRegistrations? backend,
}) async {
  final uiServices = LazyServices();
  final registrations = FrontendRegistrations(uiServices)..installAll(frontend);
  final container = UiContainer(registrations, uiServices, link: link, ready: ready, core: core, overrides: overrides);
  // Разделы модулей — **свои**, приехавшие рукопожатием: общего объекта между
  // сторонами больше нет. Правку экран отправляет обратно сообщением.
  registrations.settingsSource = container.settings;

  final app = container.get<AppController>();
  // Раздел модуля просит записать себя — снимок собирает приложение: место
  // окна и разделитель знает оно, а не контейнер.
  container.settings.modules.onSave = app.settingsChanged;
  // С этого момента командам модулей есть у кого спросить про приложение.
  if (container.context case final RuntimeContext context) {
    context.app = app;
  }
  final runtime = AppRuntime(app: app, modules: [...?backend?.modules, ...registrations.modules], services: uiServices);

  // Последними — стартовые команды модулей: им нужно готовое приложение.
  await _runStartupCommands(container, registrations);

  return runtime;
}

/// Сборка приложения, у которого ядро живёт **в другом изоляте**.
///
/// Отличие от [initModules] ровно одно — чем открыта дверь: вместо петли порт.
/// Всё остальное — и рукопожатие, и сборка интерфейса, и стартовые команды —
/// то же самое, и написано оно один раз ([_frontend]).
///
/// Списки модулей сюда не передаются вовсе: ядро собирает свои у себя, по тем
/// же спискам, — а кода через порт не ездит. Подмен служб тоже нет: подставное
/// дерево и хранилище в памяти живут в этом изоляте, и в тот не уедут. Прогон
/// поэтому идёт на петле, а изолят проверяется отдельно и живьём
/// (`docs/spec/client-server.md`, §11, урок 14).
Future<AppRuntime> initIsolated(
  List<FcFrontendModule> frontend, {
  AppOverrides overrides = const AppOverrides(),
}) async {
  final link = await IsolateLink.spawn(coreMain, (back) => CoreStartup(back, RootIsolateToken.instance));
  final ready = await link.call(const Handshake()) as CoreReady;

  // Подмены доходят только экранные: дерево и хранилище живут по ту сторону
  // порта, и подставить их отсюда нечем.
  return _frontend(frontend, link: link, ready: ready, overrides: overrides);
}

/// Стартовые команды модулей — по порядку объявления.
///
/// Идут они тем же путём, что и команда, запущенная клавишей: реестр связывает
/// их с запуском и разбирает исход. Поэтому ошибка одной из них не роняет
/// запуск, а уходит в журнал — модуль темы не смог восстановить оформление,
/// приложение всё равно должно открыться.
Future<void> _runStartupCommands(UiContainer container, FrontendRegistrations registrations) async {
  if (registrations.startupCommands.isEmpty) {
    return;
  }

  final registry = container.get<CommandRegistry>();
  for (final factory in registrations.startupCommands) {
    await registry.runToCompletion(factory(container.context));
  }
}
