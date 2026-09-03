import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import '../state/commands/help_command.dart';
import '../state/commands/palette_command.dart';
import '../state/commands/settings_command.dart';
import '../state/shell_settings.dart';
import '../ui/credentials_prompt.dart';
import '../ui/elevation_prompt.dart';

/// Оболочка приложения — то, что есть у файлового менеджера всегда.
///
/// Не модуль в смысле «можно выключить»: без движка переноса не скопировать, а
/// без справки и палитры приложение осталось бы без собственного лица. Оформлен
/// он всё равно модулем — чтобы правила были одни для всех и чтобы видно было,
/// что именно оболочка приносит.
///
/// Ядровая половина — движок и файловые работы: обход дерева и байты живут
/// там, где источники. Экранная — справка, палитра, окно настроек и вопросы о
/// секретах (`docs/spec/client-server.md`, §5.4).
class AppShell implements FcBackendModule, FcFrontendModule {
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
  void installBackend(BackendRegistry registry) {
    // Движок один на приложение: состояния у него нет, а источники узлы
    // приносят с собой — в том числе разные у источника и приёмника.
    registry.service<TreeEditor>((services) => const TreeTransferEngine());

    registry.operation(FileOperations.copy, (services) => _transfer(moves: false));
    registry.operation(FileOperations.move, (services) => _transfer(moves: true));

    registry.operation(
      FileOperations.remove,
      (services) => TaskOperation<OperationInputs, void>(
        (op, inputs) => op.delegate(
          inputs.editor.remove(),
          RemoveParams(inputs.targets, toTrash: inputs.option<bool>(FileOperations.toTrash) ?? true),
        ),
      ),
    );

    registry.operation(
      FileOperations.makeDirectory,
      (services) => TaskOperation<OperationInputs, void>((op, inputs) async {
        final parent = inputs.destination;
        final name = inputs.option<String>(FileOperations.name) ?? '';
        if (parent == null || name.isEmpty) {
          throw FsError(name, FsErrorKind.invalidName);
        }
        await op.delegate(inputs.editor.makeDirectory(), MakeDirectoryParams(parent, name));
      }),
    );

    registry.operation(
      FileOperations.measure,
      (services) => TaskOperation<OperationInputs, void>((op, inputs) async {
        final node = inputs.targets.firstOrNull;
        if (node == null) {
          return;
        }
        await op.delegate(node.provider.calculateSize(), inputs.targets);
      }),
    );

    registry.operation(
      FileOperations.rename,
      (services) => TaskOperation<OperationInputs, void>((op, inputs) async {
        final node = inputs.targets.firstOrNull;
        final name = inputs.option<String>(FileOperations.name) ?? '';
        if (node == null || name.isEmpty) {
          throw FsError(name, FsErrorKind.invalidName);
        }
        await op.delegate(inputs.editor.rename(), RenameParams(node, name));
      }),
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    // Пароль нужен файловому менеджеру всегда: архив под паролем, сервер с
    // паролем. Здесь объявлена **экранная** половина: показать вопрос и
    // принять ответ. Спрашивает же его тот, кто работает с источником, — ядро,
    // — и оно же помнит названное (`docs/spec/client-server.md`, §7.3).
    registry.service<CredentialPrompt>((services) => services.resolve<CredentialsController>());
    // Повышение прав разрезано там же и по той же причине: обнаруживает нужду
    // тот, кто до экрана не дотягивается, а спросить может только тот, у кого
    // экран есть.
    registry.service<Elevation>((services) => services.resolve<ElevationPrompt>());

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
          read: () => app.sizeScanConcurrency,
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

  /// Копирование и перенос — одна работа с одним отличием.
  ///
  /// Движок берётся у **приёмника**: выполняет дело он, один на все источники,
  /// и получить его нужно там, где заведомо умеют принимать. У источника его
  /// может не быть вовсе — это не мешает копировать из него.
  static Operation<OperationInputs, void> _transfer({required bool moves}) =>
      TaskOperation<OperationInputs, void>((op, inputs) async {
        final destination = inputs.destination;
        if (destination == null) {
          throw const FsError('', FsErrorKind.notSupported);
        }
        await op.delegate(
          moves ? inputs.editor.move() : inputs.editor.copy(),
          TransferParams(
            inputs.targets,
            destination,
            followLinks: inputs.option<bool>(FileOperations.followLinks) ?? false,
          ),
        );
      });
}

/// Разбирает список составных расширений из строки настройки.
///
/// Точка с запятой или пробел — человек напишет как привычнее, а точку в начале
/// («.tar.gz») отбрасываем: в словаре хранится хвост, а не имя файла.
List<String> _splitExtensions(String value) => [
  for (final part in value.split(RegExp(r'[;\s]+')))
    if (part.trim().isNotEmpty) part.trim().replaceFirst(RegExp(r'^\.+'), ''),
];
