import 'package:fc_api/fc_api.dart';

import '../state/commands/help_command.dart';
import '../state/commands/palette_command.dart';
import '../state/commands/settings_command.dart';
import '../state/shell_settings.dart';
import '../state/credentials_controller.dart';
import '../state/elevation_controller.dart';

/// Оболочка приложения: то, что есть у файлового менеджера всегда.
///
/// Движок файловых операций, справка и обещания клавиш: `F3` и `F4` заняты
/// заглушками, потому что просмотрщик и редактор появятся модулями, а
/// пользователь должен видеть, что место за ними закреплено.
class AppShell implements FcModule {
  const AppShell();

  /// Обещания клавиш: команды за ними появятся модулями, а сами клавиши
  /// заняты уже сейчас. Идентификаторы объявлены здесь — своих классов у
  /// заглушек нет.
  static const String viewCommand = 'file.view';
  static const String editCommand = 'file.edit';

  @override
  String get id => 'fc.shell';

  @override
  String get title => 'Application shell';

  @override
  void install(FcRegistry registry) {
    // Движок один на приложение: состояния у него нет, а провайдеров узлы
    // приносят с собой — в том числе разных у источника и приёмника.
    registry.service<TreeEditor>((services) => const TreeTransferEngine());

    // Пароль нужен файловому менеджеру всегда: архив под паролем, сервер с
    // паролем. Модуль просит службу так же, как любую другую, — и не знает,
    // ни как её спрашивают, ни где она помнит ответ.
    registry.service<Credentials>((services) => services.resolve<CredentialsController>());
    // Повышение прав — служба того же рода, что и секреты: обнаруживает нужду
    // тот, кто до экрана не дотягивается, а спросить может только ядро.
    registry.service<Elevation>((services) => services.resolve<ElevationController>());

    // Справка показывает содержимое реестра, а реестра во время объявления
    // ещё нет: команда получает не его, а способ его спросить.
    registry.command((context) => HelpCommand(registry: () => context.resolve<CommandRegistry>()));
    registry.binding(KeyBinding('F1', HelpCommand.commandId));

    // Ещё не реализованное: клавиша закреплена, кнопка показана и приглушена.
    registry.command((context) => PlaceholderCommand(id: viewCommand, label: 'View'));
    registry.command((context) => PlaceholderCommand(id: editCommand, label: 'Edit'));
    registry.binding(KeyBinding('F3', viewCommand));
    registry.binding(KeyBinding('F4', editCommand));

    // Настройки на `F9` — там, где в `mc` меню.
    //
    // Меню в этом приложении не появится: строка меню macOS остаётся системной,
    // а всё, что предложило бы меню приложения, лучше делает палитра команд —
    // она ищет по названию, показывает клавиши и не требует мыши. Настройки —
    // ближайшее к меню из того, что здесь есть, и рука ищет их там же.
    //
    // `F2` при этом освобождается: в референсе за ним «переименовать», и в
    // панельных менеджерах это самая привычная из функциональных клавиш.
    registry.command((context) => SettingsCommand(catalog: () => context.resolve<SettingsCatalog>()));
    registry.binding(KeyBinding('F9', SettingsCommand.commandId));
    // Привычка macOS. Действует и в просмотрщике, и в редакторе: настройки —
    // не про то, что сейчас на экране.
    registry.binding(KeyBinding.anywhere('Cmd-,', SettingsCommand.commandId));

    final settings = registry.settings;

    // Палитра команд: всё, что приложение умеет сейчас, по названию.
    //
    // `F2` ей, вопреки плану, не достаётся — он занят настройками. Клавиша
    // действует везде: палитра не про то, что сейчас на экране.
    registry.command(
      (context) => CommandPaletteCommand(
        registry: () => context.resolve<CommandRegistry>(),
        recent: () => settings.section(ShellSettings.new).recentCommands,
        save: settings.save,
      ),
    );
    registry.binding(KeyBinding.anywhere('Cmd-Shift-P', CommandPaletteCommand.commandId));

    // Настройки самого приложения: своего модуля у ядра нет, а выбор есть.
    registry.settingsSchema(() {
      final app = registry.services.resolve<Application>();
      return SettingsSchema([
        // Тема — выбор из установленных, и знает их служба оформления, а не
        // модуль темы: тот объявляет только себя.
        SettingsField.choice(
          'themeId',
          defaultValue: app.theme.available.first.id,
          title: 'Theme',
          options: {for (final theme in app.theme.available) theme.id: theme.title},
          read: () => app.theme.current.id,
          write: (value) => app.theme.use(value),
        ),
        SettingsField.integer(
          'sizeScanConcurrency',
          defaultValue: AppSettings.defaultSizeScanConcurrency,
          title: 'Directory size scans',
          description: 'How many directories are measured at once',
          min: 1,
          max: 64,
          read: () => app.settings.sizeScanConcurrency,
          // Через `app.settings` записать нельзя: он собирает новый объект на
          // каждый запрос, и правка уходила бы в одноразовую копию.
          write: app.setSizeScanConcurrency,
        ),
        SettingsField.text(
          'compoundExtensions',
          title: 'Compound extensions',
          description: 'Names ending in these are shown as one extension: archive.tar.gz is tar.gz',
          hint: 'cfg.json; story.tsx',
          read: () => settings.section(ShellSettings.new).compoundExtensions.join('; '),
          // Через точку с запятой — как маски в окне пометки: разделитель у
          // приложения уже свой, и заводить второй незачем.
          write: (value) => settings.section(ShellSettings.new).compoundExtensions = _splitExtensions(value),
        ),
        SettingsField.flag(
          'useBuiltinExtensions',
          defaultValue: true,
          title: 'Use the built-in list',
          description: 'tar.gz, tar.bz2, spec.ts, min.js and a few more',
          read: () => settings.section(ShellSettings.new).useBuiltinExtensions,
          write: (value) => settings.section(ShellSettings.new).useBuiltinExtensions = value,
        ),
        SettingsField.flag(
          'allowElevatedWrites',
          defaultValue: true,
          title: 'Allow elevated writes',
          description: 'Offer to save as administrator where ordinary rights are not enough',
          read: () => settings.section(ShellSettings.new).allowElevatedWrites,
          write: (value) => settings.section(ShellSettings.new).allowElevatedWrites = value,
        ),
      ], save: settings.save);
    });
  }
}

/// Разбирает список составных расширений из строки настройки.
///
/// Точка с запятой или пробел — человек напишет как привычнее, а точку в начале
/// («.tar.gz») отбрасываем: в словаре хранится хвост, а не имя файла.
List<String> _splitExtensions(String value) => [
  for (final part in value.split(RegExp(r'[;\s]+')))
    if (part.trim().isNotEmpty) part.trim().replaceFirst(RegExp(r'^\.+'), ''),
];
