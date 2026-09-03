import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_platform/fc_platform.dart';

import 'local_fs_settings.dart';
import 'local_tree_provider.dart';

/// Локальная файловая система — ядровая половина: корневой источник и всё
/// платформенное, что нужно там, где живут источники.
///
/// Оформлена модулем, как и остальное, но особого положения: без локальной ФС
/// нельзя прочитать даже собственные настройки приложения.
class LocalFileSystemBackend implements FcBackendModule {
  const LocalFileSystemBackend();

  @override
  String get id => 'fc.local_fs';

  @override
  String get title => 'Local file system';

  @override
  void installBackend(BackendRegistry registry) {
    // Раздел настроек берётся не сейчас, а по надобности: сам файл настроек
    // лежит в домашнем каталоге, а где он — знает провайдер, который здесь
    // только создаётся.
    final settings = registry.settings;

    registry.rootProvider(
      (services) => LocalTreeProvider(
        settings: () => settings.section(LocalFsSettings.new),
        // Чем запускать оболочку — вещь пользовательская, и живёт она в
        // настройках терминала. Спрашивается необязательно и лениво: без
        // модуля терминала объявить её некому, и тогда берётся `$SHELL`.
        shellName: () => services.resolveAll<ShellPreference>().firstOrNull?.shell ?? '',
        // Повышение прав — тоже необязательно и тоже лениво: службу объявляет
        // ядро, а провайдер создаётся раньше него.
        elevation: () => services.resolveAll<ElevatedWrites>().firstOrNull,
      ),
    );

    // Оболочка **этой машины** — службой, отдельно от провайдера.
    //
    // Провайдер её тоже умеет (панель на локальной ФС), но спросить его можно
    // только через панель, а панели открываются позже служб. Терминалу же она
    // нужна как раз до всяких панелей — чтобы завести оболочку заранее, а не в
    // тот миг, когда человек уже нажал `Ctrl-O`.
    registry.service<ShellHost>(
      (services) => LocalShellHost(
        launcher: const SystemPtyLauncher(),
        shellName: () => services.resolveAll<ShellPreference>().firstOrNull?.shell ?? '',
      ),
    );

    // Место для временных файлов: им пользуются те, кому нужен настоящий файл
    // на диске, — архиватор и будущие сетевые источники.
    registry.service<StagingArea>((services) => const LocalStagingArea());

    // Запуск программ: им пользуются модули, которые стоят над внешним
    // инструментом, — архиватор 7z и будущие сетевые источники.
    registry.service<ProcessRunner>((services) => const LocalProcessRunner());
  }
}
