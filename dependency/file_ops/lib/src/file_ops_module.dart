import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'clipboard_commands.dart';
import 'file_ops_settings.dart';
import 'multi_rename_command.dart';
import 'rename_batch.dart';
import 'copy_path_command.dart';
import 'file_commands.dart';
import 'transfer_commands.dart';

/// Файловые операции: создать каталог, удалить, скопировать, перенести.
///
/// Всё, ради чего файловый менеджер и заводят. Отдельным модулем — по той же
/// причине, что и навигация: это набор действий, а не устройство приложения.
/// Работают они через [TreeEditor], поэтому источник и приёмник могут быть
/// из разных провайдеров, и модулю это безразлично.
class FileOps implements FcBackendModule, FcFrontendModule {
  const FileOps();

  static const String commandId = 'fc.file_ops';

  @override
  String get id => commandId;

  @override
  String get title => 'File operations';

  /// Переименование пачки — работа ядра: там живут узлы и там же видно, чьё
  /// имя освободилось. Объявляет её сам модуль, а не оболочка: работа
  /// принадлежит файловым операциям (`docs/spec/multi-rename.md`, §2).
  @override
  void installBackend(BackendRegistry registry) {
    registry.operation(
      RenameOperations.batch,
      (services) => RenameBatchWork(strings: services.resolve<Strings>()).operation(),
    );
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела уже
    // неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    FileOpsSettings settingsOf() => settings.section(FileOpsSettings.new);

    registry.strings('ru', _russian);
    registry.plurals('ru', _plurals);

    registry.command((context) => MakeDirectoryCommand());
    registry.command((context) => RenameCommand());
    // Имена считает экран этой же командой, работе едут готовые пары
    // (`docs/spec/multi-rename.md`, §2).
    registry.command(
      (context) => MultiRenameCommand(context.resolve<FileNaming>(), settings: settingsOf, save: settings.save),
    );
    registry.command((context) => RemoveCommand());
    registry.command((context) => RemovePermanentlyCommand());
    registry.command((context) => CopyCommand());
    registry.command((context) => MoveCommand());
    // Буфер текстовый, а не файловый: адрес — это строка, и класть её есть
    // куда всегда (`docs/spec/file-clipboard.md`, §7).
    registry.command((context) => CopyPathCommand(context));

    // Файловый буфер: служба приходит модулем приложения, и без неё эти
    // команды невыполнимы (`docs/spec/file-clipboard.md`, §2).
    registry.command((context) => ClipboardCopyCommand(context));
    registry.command((context) => ClipboardCutCommand(context));
    registry.command((context) => ClipboardPasteCommand(context, forcesMove: false));
    registry.command((context) => ClipboardPasteCommand(context, forcesMove: true));

    registry.binding(KeyBinding('F5', CopyCommand.commandId, context: KeyContext.panel));
    registry.binding(KeyBinding('F6', MoveCommand.commandId, context: KeyContext.panel));
    registry.binding(KeyBinding('F7', MakeDirectoryCommand.commandId, context: KeyContext.panel));
    // Shift-F6 — там же, где переименование во всех коммандерах: рядом с
    // переносом, потому что это его ближайший родственник.
    registry.binding(KeyBinding('Shift-F6', RenameCommand.commandId, context: KeyContext.panel));
    // `Ctrl-M` — привычка Total Commander; `Cmd-M` на macOS занят системой
    // (`docs/keyboard.md`, «Занятые системой сочетания»).
    registry.binding(KeyBinding('Ctrl-M', MultiRenameCommand.commandId, context: KeyContext.panel));
    // На macOS F-клавиши по умолчанию отданы системе (F7 — «предыдущий трек»),
    // и до приложения нажатие не доходит. Привычное сочетание из Finder
    // работает без настройки клавиатуры.
    registry.binding(KeyBinding('F8', RemoveCommand.commandId, context: KeyContext.panel));
    registry.binding(KeyBinding('Shift-F8', RemovePermanentlyCommand.commandId, context: KeyContext.panel));
    // То же сочетание, что у «Copy as Pathname» в Finder: кто пришёл оттуда,
    // получает привычку без настройки.
    registry.binding(KeyBinding('Alt-Cmd-C', CopyPathCommand.commandId, context: KeyContext.panel));
    registry.binding(KeyBinding('Cmd-C', ClipboardCopyCommand.commandId, context: KeyContext.panel));
    registry.binding(KeyBinding('Cmd-X', ClipboardCutCommand.commandId, context: KeyContext.panel));
    registry.binding(KeyBinding('Cmd-V', ClipboardPasteCommand.copyId, context: KeyContext.panel));
    // Привычка Finder: копируют, а переносят клавишей вставки.
    registry.binding(KeyBinding('Alt-Cmd-V', ClipboardPasteCommand.moveId, context: KeyContext.panel));
  }
}

/// Русские строки файловых операций.
const Map<String, String> _russian = {
  'Delete failed': 'Удалить не вышло',

  // Групповое переименование (`docs/spec/multi-rename.md`).
  'Multi-rename': 'Переименовать разом',
  // Наборы правил. «Preset», «Delete set» и «A set without a name cannot be
  // chosen» переводит оболочка — там же, где наборы настроек: одно и то же
  // слово дважды в словарях не объявляют.
  'Not saved': 'Не сохранён',
  'Save the rules': 'Сохранение набора',
  'My rules': 'Мои правила',
  'Delete «{name}»? The rules in the window stay as they are.':
      'Удалить «{name}»? Набранное в окне останется как есть.',
  'Rename the selected items at once, with a preview': 'Переименовать помеченное разом, с предпросмотром',
  'Name': 'Имя',
  'Extension': 'Расширение',
  'Find': 'Найти',
  'Replace with': 'Заменить на',
  'Regular expression': 'Регулярное выражение',
  'Case sensitive': 'Различать регистр',
  'Name case': 'Регистр имени',
  'Extension case': 'Регистр расширения',
  'Counter': 'Счётчик',
  'Start at': 'с',
  'Step by': 'шаг',
  'Digits': 'разрядов',
  'Was': 'Было',
  'Becomes': 'Станет',
  'Renaming…': 'Переименование…',
  'Multi-rename failed': 'Переименовать разом не вышло',
  'Skip': 'Пропустить',
  'Skip all': 'Пропустить все',
  'Cancel': 'Отмена',
  'Unchanged': 'без изменений',
  'UPPERCASE': 'ВЕРХНИЙ',
  'lowercase': 'нижний',
  'First capital': 'Первая заглавная',
  'Every Word': 'Каждое Слово',
  'File operations': 'Файловые операции',

  // Перенос.
  'Copy': 'Копировать',
  'Copy the selected items to the other panel': 'Копировать выбранное в соседнюю панель',
  'Copying…': 'Копирование…',
  'Move': 'Перенести',
  'Move the selected items to the other panel': 'Перенести выбранное в соседнюю панель',
  'Moving…': 'Перенос…',
  'Copy path': 'Скопировать путь',
  'Copy to clipboard': 'Скопировать в буфер',
  'Put the selected items into the clipboard': 'Положить выбранное в буфер обмена',
  'Cut to clipboard': 'Вырезать в буфер',
  'Put the selected items into the clipboard to be moved': 'Положить выбранное в буфер обмена для переноса',
  'Paste': 'Вставить',
  'Put the clipboard items into this panel': 'Вставить то, что лежит в буфере, в эту панель',
  'Paste as move': 'Вставить переносом',
  'Move the clipboard items into this panel': 'Перенести в эту панель то, что лежит в буфере',
  'The clipboard has no files': 'В буфере обмена нет файлов',
  'Copy the address of the selected items to the clipboard': 'Скопировать адрес выбранного в буфер обмена',
  'From': 'Откуда',
  'To': 'Куда',
  'Destination path': 'Путь назначения',
  'Follow symlinks': 'Идти по ссылкам',

  // Каталог.
  'Mk Dir': 'Каталог',
  'Create a directory in the active panel': 'Создать каталог в активной панели',
  'Create': 'Создать',
  'Inside': 'Внутри',
  'Make directory': 'Создать каталог',
  'Directory name': 'Имя каталога',

  // Удаление.
  'Delete': 'Удалить',
  'Move the selected items to the trash': 'Отправить выбранное в корзину',
  'Delete !': 'Удалить !',
  'Delete the selected items without the trash': 'Удалить выбранное мимо корзины',
  'Delete permanently': 'Удалить навсегда',
  'Deleting…': 'Удаление…',
  'Move {what} to Trash?': 'Отправить {what} в корзину?',
  'Delete {what} permanently? This cannot be undone.': 'Удалить {what} навсегда? Это не отменить.',

  // Переименование.
  'Rename': 'Переименовать',
  'Rename the item under the cursor': 'Переименовать объект под курсором',
  'New name': 'Новое имя',
};

/// Множественные формы: ключ — та форма, которую называют на месте.
const Map<String, PluralForms> _plurals = {
  '{n} to rename': (one: '{n} переименуется', few: '{n} переименуются', many: '{n} переименуются'),
  '{n} collisions': (one: '{n} столкновение', few: '{n} столкновения', many: '{n} столкновений'),
  'Copied {n} addresses': (one: 'Скопирован {n} адрес', few: 'Скопировано {n} адреса', many: 'Скопировано {n} адресов'),
  'Copied {n} items': (one: 'Скопирован {n} объект', few: 'Скопировано {n} объекта', many: 'Скопировано {n} объектов'),
  '{n} items ready to move': (
    one: '{n} объект готов к переносу',
    few: '{n} объекта готовы к переносу',
    many: '{n} объектов готовы к переносу',
  ),
  '{n} items': (one: '{n} объект', few: '{n} объекта', many: '{n} объектов'),
  // «Откуда», когда цели лежат в разных каталогах: перечислять их негде.
  '{n} sources': (one: '{n} источник', few: '{n} источника', many: '{n} источников'),
};
