import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import '../bootstrap/language.dart';
import '../state/background_tasks.dart';
import '../state/background_tasks_state.dart';
import '../state/commands/background_commands.dart';
import '../state/commands/help_command.dart';
import '../state/commands/palette_command.dart';
import '../state/commands/settings_command.dart';
import '../state/shell_settings.dart';
import '../ui/credentials_prompt.dart';
import '../ui/elevation_prompt.dart';
import '../view/background_tasks_view.dart';

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
    // Своя половина словаря: вехи работы панели пишет ядро, и переводит их оно
    // же (`docs/spec/localization.md`, §5).
    registry.strings('ru', _coreRussian);

    // Движок один на приложение: состояния у него нет, а источники узлы
    // приносят с собой — в том числе разные у источника и приёмника.
    registry.service<TreeEditor>((services) => TreeTransferEngine(strings: services.resolve<Strings>()));

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
    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

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

    // Список фоновых работ под панелью: обычная область со своим курсором и
    // клавишами (`docs/spec/background-operations.md`).
    registry.view<BackgroundTasksState>((context, state) => BackgroundTasksView(state: state));
    registry.command((context) => FocusBackgroundCommand());
    registry.command((context) => LeaveBackgroundCommand());
    registry.command((context) => MoveBackgroundCursorCommand(down: false));
    registry.command((context) => MoveBackgroundCursorCommand(down: true));
    registry.command((context) => ShowBackgroundTaskCommand());
    registry.command((context) => CancelBackgroundTaskCommand());
    // `Cmd-B` действует везде: список работ не про то, что сейчас на экране.
    registry.binding(KeyBinding.anywhere('Cmd-B', FocusBackgroundCommand.commandId));
    // Остальное — только когда клавиши у списка. Иначе `Bsp` в панели значил бы
    // «наверх», а `Enter` — «войти», и отнимать их у панели нельзя.
    registry.binding(KeyBinding.inState<BackgroundTasksState>('Up', MoveBackgroundCursorCommand.upId));
    registry.binding(KeyBinding.inState<BackgroundTasksState>('Down', MoveBackgroundCursorCommand.downId));
    registry.binding(KeyBinding.inState<BackgroundTasksState>('Enter', ShowBackgroundTaskCommand.commandId));
    registry.binding(KeyBinding.inState<BackgroundTasksState>('Esc', LeaveBackgroundCommand.commandId));
    // Две клавиши на одно действие: на маленькой клавиатуре `Del` нет вовсе, а
    // на большой рука тянется к нему.
    registry.binding(KeyBinding.inState<BackgroundTasksState>('Bsp', CancelBackgroundTaskCommand.commandId));
    registry.binding(KeyBinding.inState<BackgroundTasksState>('Del', CancelBackgroundTaskCommand.commandId));
    // Сторож, который держит список в области ровно тогда, когда работы есть.
    // Стартовой командой, потому что приложение к этому времени уже собрано.
    registry.startup((context) => _WatchBackgroundTasksCommand(context));

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
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        // Тема — выбор из установленных, и знает их служба оформления, а не
        // модуль темы: тот объявляет только себя.
        SettingsField.choice(
          'themeId',
          defaultValue: app.theme.available.first.id,
          title: strings.tr('Theme'),
          // Название темы приходит значением — переводит его тот, кто показывает.
          options: {for (final theme in app.theme.available) theme.id: strings.tr(theme.title)},
          read: () => app.theme.current.id,
          write: (value) => app.theme.use(value),
        ),
        // Язык впереди темы: на нём написано всё остальное в этом окне.
        SettingsField.choice(
          'language',
          defaultValue: systemLanguage,
          title: strings.tr('Language'),
          description: strings.tr('Interface language; «System» follows the machine'),
          options: {systemLanguage: strings.tr('System'), 'en': 'English', 'ru': 'Русский'},
          read: () => settings.section(ShellSettings.new).language,
          write: (value) {
            settings.section(ShellSettings.new).language = value;
            // Реестр за файлом настроек не следит, а перерисоваться должен весь
            // экран разом (`docs/spec/localization.md`, §10).
            (app.strings as StringsRegistry).refresh();
          },
        ),
        SettingsField.integer(
          'sizeScanConcurrency',
          defaultValue: AppSettings.defaultSizeScanConcurrency,
          title: strings.tr('Directory size scans'),
          description: strings.tr('How many directories are measured at once'),
          min: 1,
          max: 64,
          read: () => app.sizeScanConcurrency,
          write: app.setSizeScanConcurrency,
        ),
        SettingsField.text(
          'compoundExtensions',
          title: strings.tr('Compound extensions'),
          description: strings.tr('Names ending in these are shown as one extension: archive.tar.gz is tar.gz'),
          hint: 'cfg.json; story.tsx',
          read: () => settings.section(ShellSettings.new).compoundExtensions.join('; '),
          // Через точку с запятой — как маски в окне пометки: разделитель у
          // приложения уже свой, и заводить второй незачем.
          write: (value) => settings.section(ShellSettings.new).compoundExtensions = _splitExtensions(value),
        ),
        SettingsField.flag(
          'useBuiltinExtensions',
          defaultValue: true,
          title: strings.tr('Use the built-in list'),
          description: strings.tr('tar.gz, tar.bz2, spec.ts, min.js and a few more'),
          read: () => settings.section(ShellSettings.new).useBuiltinExtensions,
          write: (value) => settings.section(ShellSettings.new).useBuiltinExtensions = value,
        ),
        SettingsField.flag(
          'listingCache',
          defaultValue: true,
          title: strings.tr('Remember directory listings'),
          description: strings.tr('A directory you have already visited shows at once and reloads in the background'),
          read: () => settings.section(ShellSettings.new).listingCache,
          write: (value) => settings.section(ShellSettings.new).listingCache = value,
        ),
        SettingsField.integer(
          'listingCacheLimit',
          defaultValue: ShellSettings.defaultListingCacheLimit,
          title: strings.tr('Listings remembered'),
          description: strings.tr('How many directories are kept in memory'),
          min: 1,
          max: 1024,
          read: () => settings.section(ShellSettings.new).listingCacheLimit,
          write: (value) => settings.section(ShellSettings.new).listingCacheLimit = value,
        ),
        SettingsField.integer(
          'listingCacheTtl',
          defaultValue: ShellSettings.defaultListingCacheTtl,
          title: strings.tr('Listing kept for'),
          description: strings.tr('Seconds after which a remembered listing is no longer shown'),
          min: 1,
          max: 86400,
          read: () => settings.section(ShellSettings.new).listingCacheTtl,
          write: (value) => settings.section(ShellSettings.new).listingCacheTtl = value,
        ),
        SettingsField.flag(
          'allowElevatedWrites',
          defaultValue: true,
          title: strings.tr('Allow elevated writes'),
          description: strings.tr('Offer to save as administrator where ordinary rights are not enough'),
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

/// Заводит сторожа списка фоновых работ.
///
/// Стартовой командой и по той же причине, что у перетаскивания: службе нужно
/// собранное приложение, а во время объявления модуля его ещё нет.
class _WatchBackgroundTasksCommand extends AppCommand {
  _WatchBackgroundTasksCommand(this.context);

  final FcContext context;

  @override
  String get id => 'background.watch';

  @override
  String get label => tr('Watch background tasks');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext _) async {
    BackgroundTasks(context.app);
  }
}

/// Русские строки оболочки — экранная половина.
///
/// Здесь же живут подписи общих частей окон (`fc_ui_kit`): своего модуля у них
/// нет, а показывает их оболочка.
const Map<String, String> _russian = {
  'Next task': 'Следующая работа',
  'Previous task': 'Предыдущая работа',
  'Abort the operation?': 'Прервать работу?',
  'Abort': 'Прервать',
  'Application shell': 'Оболочка',
  'Other': 'Прочее',

  // Команды оболочки.
  'Help': 'Справка',
  'Everything the application remembers by your choice': 'Всё, что приложение помнит по вашему выбору',
  'Settings': 'Настройки',
  'Commands': 'Команды',
  'Everything the application can do right now, by name': 'Всё, что приложение умеет сейчас, — по названию',
  'Command': 'Команда',
  'Command list is not available': 'Список команд недоступен',
  'Background tasks': 'Фоновые работы',
  'Move the input to the list of tasks running in background': 'Перевести ввод в список работ, ушедших в фон',
  'Show task': 'Показать работу',
  'Cancel task': 'Прервать работу',
  'Stop the selected background task; a finished one is dismissed':
      'Прервать выбранную фоновую работу; законченную — забыть',
  'Watch background tasks': 'Следить за фоновыми работами',

  // Справка.
  'Left panel': 'Левая панель',
  'Right panel': 'Правая панель',
  'Active panel': 'Активная панель',
  'Left': 'Левая',
  'Right': 'Правая',
  'Split': 'Разделитель',
  '{percent}% left': '{percent}% слева',
  'shown': 'показаны',
  'hidden': 'скрыты',
  'Sort': 'Сортировка',
  'Columns': 'Колонки',
  'Directory scans': 'Обход каталогов',
  '{count} at a time': 'по {count} за раз',
  'Window': 'Окно',

  // Окно ошибки.
  'Unexpected error': 'Непредвиденная ошибка',
  'Unexpected error (1 of {count})': 'Непредвиденная ошибка (1 из {count})',
  'Report': 'Отчёт',
  'Error report copied': 'Отчёт скопирован',
  'Message': 'Сообщение',
  'Time': 'Время',
  'Repeated': 'Повторилась',
  'While': 'При',
  'Stack': 'Стек',
  'No stack trace': 'Стека нет',

  // Общие части окон.
  'Stage': 'Этап',
  'Item': 'Объект',
  'Speed': 'Скорость',
  'Total': 'Всего',
  'Reset': 'Вернуть',
  'Search settings': 'Искать настройку',
  'Unlock': 'Открыть',
  'Wrong password': 'Пароль не подошёл',
  'Password': 'Пароль',
  'User name': 'Имя пользователя',
  'Administrator rights': 'Права администратора',
  '{action} {path}\non {where} as administrator?': '{action} {path}\nна {where} от администратора?',
  'Continue': 'Продолжить',

  // Перетаскивание.
  'Drag and drop': 'Перетаскивание',
  'Install drag and drop': 'Включить перетаскивание',
  'Drop into the same panel': 'Бросать в ту же панель',
  'Allow dropping files back into the panel they are dragged from':
      'Разрешить бросать файлы обратно в ту панель, откуда их тянут',
  'Could not hand over «{name}»: {error}': 'Не удалось отдать «{name}»: {error}',
  'Extracting «{name}»': 'Распаковка «{name}»',

  // Настройки приложения.
  'Theme': 'Оформление',
  'Language': 'Язык',
  'Interface language; «System» follows the machine': 'Язык интерфейса; «Системный» — как у машины',
  'System': 'Системный',
  'Directory size scans': 'Обходов каталогов разом',
  'How many directories are measured at once': 'Сколько каталогов считается одновременно',
  'Compound extensions': 'Составные расширения',
  'Names ending in these are shown as one extension: archive.tar.gz is tar.gz':
      'Имена с таким концом показываются одним расширением: archive.tar.gz — это tar.gz',
  'Use the built-in list': 'Пользоваться встроенным списком',
  'tar.gz, tar.bz2, spec.ts, min.js and a few more': 'tar.gz, tar.bz2, spec.ts, min.js и ещё несколько',
  'Allow elevated writes': 'Разрешать запись от администратора',
  'Offer to save as administrator where ordinary rights are not enough':
      'Предлагать сохранить от администратора там, где обычных прав не хватило',
  'Remember directory listings': 'Помнить содержимое каталогов',
  'A directory you have already visited shows at once and reloads in the background':
      'Каталог, где вы уже были, показывается сразу и перечитывается фоном',
  'Listings remembered': 'Каталогов в памяти',
  'How many directories are kept in memory': 'Сколько каталогов держать в памяти',
  'Listing kept for': 'Запись годна',
  'Seconds after which a remembered listing is no longer shown':
      'Через сколько секунд запомненный список перестаёт показываться',
};

/// Множественные формы оболочки.
const Map<String, PluralForms> _plurals = {'{n} times': (one: '{n} раз', few: '{n} раза', many: '{n} раз')};

/// Русские строки оболочки — ядровая половина.
const Map<String, String> _coreRussian = {
  'Loading…': 'Чтение…',
  'Opening {name}…': 'Открывается {name}…',
  'Measuring directories…': 'Считаются размеры каталогов…',
  'Administrator rights': 'Права администратора',
  '{action} {path} on {where} as administrator': '{action} {path} на {where} от администратора',

  // Движок переноса: этапы работы и вопросы по её ходу.
  'copying': 'копирование',
  'moving': 'перенос',
  'deleting': 'удаление',
  'sending back': 'отправка обратно',
  'Overwrite': 'Заменить',
  'Overwrite all': 'Заменить все',
  'Skip': 'Пропустить',
  'Skip all': 'Пропустить все',
  'Proceed': 'Начать',
  'Retry': 'Повторить',
  'The link «{name}» points into the directory being copied': 'Ссылка «{name}» ведёт внутрь копируемого каталога',
  'Cannot store the link «{name}» as a link here': 'Здесь нельзя сохранить «{name}» ссылкой',
  'Could not send «{name}» back: {error}': 'Не удалось отправить «{name}» обратно: {error}',
};
