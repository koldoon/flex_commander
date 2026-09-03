import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'local_fs_settings.dart';
import 'local_tree_provider.dart';

/// Локальная файловая система: корневой источник и всё платформенное.
///
/// Один класс на обе стороны, но половины у него разные по существу: дереву
/// нужны диск, временные файлы и запуск программ, а экрану — окно, буфер
/// обмена и открытие системой. Платформенный канал живёт в том изоляте,
/// который рисует, и это не вкус, а условие.
///
/// Оформлена модулем, как и остальное, но особого положения: без локальной ФС
/// нельзя прочитать даже собственные настройки приложения.
class LocalFileSystem implements FcBackendModule, FcFrontendModule {
  const LocalFileSystem();

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

  @override
  void installFrontend(FrontendRegistry registry) {
    final settings = registry.settings;

    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.integer(
          'copyProgressMinBytes',
          defaultValue: LocalFsSettings.defaultCopyProgressMinBytes,
          title: 'Show progress inside a file from',
          unit: 'bytes',
          description: 'Below this size a copy is counted whole: the progress costs more than the copy',
          min: 0,
          max: 1024 * 1024 * 1024,
          read: () => settings.section(LocalFsSettings.new).copyProgressMinBytes,
          write: (value) => settings.section(LocalFsSettings.new).copyProgressMinBytes = value,
        ),
      ], save: settings.save),
    );

    // Буфер обмена: им пользуется просмотрщик, а дальше — команды «скопировать
    // путь» и «скопировать список имён».
    registry.service<ClipboardService>((services) => const SystemClipboard());

    // Отдать файл системной программе — действие экранное: за ним человек
    // уходит из приложения. Дереву оно ни к чему, а путь ему приносят готовым.
    registry.service<SystemOpener>((services) => openWithSystem);
    registry.service<WindowService>((services) => PluginWindowService());
  }
}
