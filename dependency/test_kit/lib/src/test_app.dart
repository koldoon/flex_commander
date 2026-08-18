import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/modules/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_window_service.dart';
import 'in_memory_settings_store.dart';

/// Платформенные службы для тестов.
///
/// Приложение собирается без модуля локальной файловой системы — дерево
/// подставное, — но кому-то из модулей платформенная служба всё же нужна.
/// Здесь она есть и ничего не делает; модуль, установленный после, заменит её
/// своей: службы разрешаются по типу, и последнее объявление выигрывает.
class TestPlatform implements FcModule {
  const TestPlatform();

  @override
  String get id => 'test.platform';

  @override
  String get title => 'Test platform';

  @override
  void install(FcRegistrar registrar) {
    registrar.service<SystemOpener>((services) => (path) async {});
  }
}

/// Приложение целиком, но на подставках: дерево в памяти, окно без системы,
/// настройки в памяти.
///
/// Так тесты модуля проверяют не набор классов, а работающее приложение с этим
/// модулем: команда, поставленная модулем, доходит до реестра, привязка — до
/// клавиатуры, а всё вместе живёт по тем же правилам, что и в настоящем запуске.
///
/// Оболочка ([AppShell]) и подставная платформа ([TestPlatform]) добавляются
/// всегда: без движка файловых операций панель не собрать, а модуль не обязан
/// знать ни о нём, ни о том, чем открываются файлы в системе. Приложение
/// закрывается вместе с тестом.
Future<AppRuntime> testApp({
  required TreeProvider provider,
  List<FcModule> modules = const [],
  AppSettings? settings,
  WindowService? window,
  String homePath = '/home',
}) async {
  // Настройки в памяти: в виджет-тестах время поддельное, и настоящее чтение
  // с диска не завершилось бы никогда.
  final store = InMemorySettingsStore(settings: settings, homePath: homePath);

  final runtime = await initModules(
    [const AppShell(), const TestPlatform(), ...modules],
    overrides: AppOverrides(
      provider: provider,
      store: store,
      window: window ?? FakeWindowService(),
      // Отложенная запись настроек не должна пережить тест: таймер, оставшийся
      // висеть после окна, роняет виджет-тест — и правильно делает.
      saveDelay: const Duration(milliseconds: 5),
    ),
  );
  addTearDown(runtime.dispose);

  return runtime;
}
