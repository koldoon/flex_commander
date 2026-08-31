import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/modules/app_shell.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_clipboard.dart';
import 'fake_process_runner.dart';
import 'fake_window_service.dart';
import 'in_memory_settings_store.dart';

/// Платформенные службы для тестов.
///
/// Приложение собирается без модуля локальной файловой системы — дерево
/// подставное, — но кому-то из модулей платформенная служба всё же нужна.
/// Здесь она есть и ничего не делает; модуль, установленный после, заменит её
/// своей: службы разрешаются по типу, и последнее объявление выигрывает.
class TestPlatform implements FcModule {
  const TestPlatform({this.processes, this.clipboard});

  /// Подставная программа для тех, кто стоит над внешним инструментом.
  /// Пусто — запускатель, у которого не установлено ничего.
  final ProcessRunner? processes;

  /// Буфер обмена. Пусто — свой, в памяти: настоящий буфер машины прогон
  /// трогать не должен.
  final FakeClipboard? clipboard;

  @override
  String get id => 'test.platform';

  @override
  String get title => 'Test platform';

  @override
  void install(FcRegistry registry) {
    registry.service<SystemOpener>((services) => (path) async {});

    // Место под временные файлы — настоящее: тем, кому оно нужно (архиватор),
    // нужен и настоящий файл, по которому можно ходить.
    registry.service<StagingArea>((services) => const LocalStagingArea());

    // Внешних программ в тестах нет: по умолчанию запускатель отвечает
    // «не установлено», а тест модуля подставляет свой сценарий.
    registry.service<ProcessRunner>((services) => processes ?? FakeProcessRunner(executables: const {}));

    // Буфер обмена — в памяти: человек за машиной в это время тоже что-то
    // копирует, и стирать ему это прогоном нельзя.
    final clipboard = this.clipboard ?? FakeClipboard();
    registry.service<ClipboardService>((services) => clipboard);
  }
}

/// Приложение целиком, но на подставках: дерево в памяти, окно без системы,
/// настройки в памяти.
///
/// Так тесты модуля проверяют не набор классов, а работающее приложение с этим
/// модулем: команда, поставленная модулем, доходит до реестра, привязка — до
/// клавиатуры, а всё вместе живёт по тем же правилам, что и в настоящем запуске.
///
/// Оболочка ([AppShell]), подставная платформа ([TestPlatform]) и оформление
/// по умолчанию ([DefaultTheme]) добавляются всегда: без движка файловых
/// операций панель не собрать, без темы — не покрасить, а модуль не обязан
/// знать ни о том, ни о другом. Приложение закрывается вместе с тестом.
Future<AppRuntime> testApp({
  required TreeProvider provider,

  /// Источник правой панели, если он должен отличаться от левой.
  TreeProvider? rightProvider,
  List<FcModule> modules = const [],
  AppSettings? settings,
  WindowService? window,

  /// Подставная программа для модулей, стоящих над внешним инструментом.
  ProcessRunner? processes,

  /// Буфер обмена, если тесту нужно посмотреть, что в него положили.
  FakeClipboard? clipboard,

  /// Сколько висит всплывающее сообщение: тесту про сами сообщения нужно
  /// подольше, остальным — чтобы таймер не пережил проверку.
  Duration? toastDuration,
  InMemorySettingsStore? store,
  String homePath = '/home',
}) async {
  // Настройки в памяти: в виджет-тестах время поддельное, и настоящее чтение
  // с диска не завершилось бы никогда.
  final settingsStore = store ?? InMemorySettingsStore(settings: settings, homePath: homePath);

  final runtime = await initModules(
    [const AppShell(), TestPlatform(processes: processes, clipboard: clipboard), const DefaultTheme(), ...modules],
    overrides: AppOverrides(
      provider: provider,
      rightProvider: rightProvider,
      store: settingsStore,
      window: window ?? FakeWindowService(),
      // Отложенная запись настроек не должна пережить тест: таймер, оставшийся
      // висеть после окна, роняет виджет-тест — и правильно делает.
      saveDelay: const Duration(milliseconds: 5),
      // Сообщение живёт ровно столько, сколько нужно тесту, чтобы его увидеть:
      // висящий таймер роняет виджет-тест.
      toastDuration: toastDuration ?? const Duration(milliseconds: 5),
    ),
  );
  addTearDown(runtime.dispose);

  return runtime;
}
