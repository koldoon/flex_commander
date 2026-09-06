import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'editor_commands.dart';
import 'editor_saving.dart';
import 'editor_screen.dart';
import 'editor_settings.dart';
import 'editor_view.dart';
import 'editor_work.dart';

/// Редактор текста: экран правки и запись файла.
///
/// Один класс на обе стороны. Половины у него разные по существу: буфер, его
/// отмены и поиск по тексту — на экране, а запись — там, где лежит файл, и
/// иначе быть не может.
class TextEditor implements FcBackendModule, FcFrontendModule {
  const TextEditor();

  /// Поиск: команды общие с просмотрщиком, идентификаторы свои.
  static const String findCommandId = 'editor.find';
  static const String findNextCommandId = 'editor.findNext';
  static const String findPreviousCommandId = 'editor.findPrevious';

  @override
  String get id => 'fc.editor';

  @override
  String get title => 'Text editor';

  @override
  void installBackend(BackendRegistry registry) {
    registry.operation(EditorWork.kind, (services) => EditorSaving.operation());
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    // Что рисует состояние, объявляет тот же модуль, который его завёл.
    registry.view<EditorScreen>((context, state) => EditorView(screen: state));
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    EditorSettings settingsOf() => settings.section(EditorSettings.new);

    // `F4` уже закреплена оболочкой за этим идентификатором — команда занимает
    // место заглушки.
    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'wordWrap',
          defaultValue: false,
          title: strings.tr('Wrap long lines'),
          read: () => settingsOf().wordWrap,
          write: (value) => settingsOf().wordWrap = value,
        ),
        SettingsField.flag(
          'showLineNumbers',
          defaultValue: true,
          title: strings.tr('Show line numbers'),
          read: () => settingsOf().showLineNumbers,
          write: (value) => settingsOf().showLineNumbers = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          defaultValue: EditorSettings.defaultMaxFileSize,
          title: strings.tr('Largest file to open'),
          unit: strings.tr('bytes'),
          min: 1024,
          max: 100 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
      ], save: settings.save);
    });

    registry.command((context) => EditFileCommand(settings: settingsOf(), onSettingsChanged: settings.save));

    registry.command((context) => SaveFileCommand());
    registry.command((context) => CloseEditorCommand());
    registry.command((context) => ToggleEditorWrapCommand());
    registry.command((context) => ToggleEditorNumbersCommand());

    registry.command((context) => FcFindTextCommand(id: findCommandId, screenId: EditorScreen.screenId));
    registry.command((context) => FcFindNextCommand(id: findNextCommandId, screenId: EditorScreen.screenId));
    registry.command((context) => FcFindPreviousCommand(id: findPreviousCommandId, screenId: EditorScreen.screenId));

    registry.binding(KeyBinding.inState<EditorScreen>('F2', SaveFileCommand.commandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Esc', CloseEditorCommand.commandId));
    registry.binding(KeyBinding.inState<EditorScreen>('F10', CloseEditorCommand.commandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Cmd-S', SaveFileCommand.commandId));
    registry.binding(KeyBinding.inState<EditorScreen>('F7', findCommandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Cmd-F', findCommandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Shift-F7', findNextCommandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Cmd-G', findNextCommandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Shift-Cmd-G', findPreviousCommandId));
    registry.binding(KeyBinding.inState<EditorScreen>('F9', ToggleEditorNumbersCommand.commandId));
    registry.binding(KeyBinding.inState<EditorScreen>('Cmd-W', ToggleEditorWrapCommand.commandId));
  }
}

/// Русские строки редактора.
const Map<String, String> _russian = {
  'Find': 'Найти',
  'Find text': 'Найти текст',
  'Find text in the document': 'Найти строку в показанном тексте',
  'Find Next': 'Найти дальше',
  'Go to the next match': 'Перейти к следующему совпадению',
  'Find Previous': 'Найти раньше',
  'Go to the previous match': 'Перейти к предыдущему совпадению',
  'Text': 'Текст',
  'Case sensitive': 'Различать регистр',
  'Regular expression': 'Регулярное выражение',
  'Nothing to find': 'Искать нечего',
  'Not a valid expression': 'Это не выражение',
  'Not found: {what}': 'Не найдено: {what}',
  'Match {index} of {count}': 'Совпадение {index} из {count}',
  'Save changes': 'Сохранение изменений',
  'Unsaved changes': 'Несохранённые изменения',
  'Text editor': 'Редактор текста',
  'Edit': 'Править',
  'Open the file under the cursor for editing': 'Открыть файл под курсором на правку',
  'Save': 'Сохранить',
  'Write the changes back to the file': 'Записать изменения обратно в файл',
  'Saved {name}': 'Сохранён {name}',
  'Quit': 'Выйти',
  'Close the editor': 'Закрыть редактор',
  'Discard': 'Не сохранять',
  'Save changes to {path}?': 'Сохранить изменения в {path}?',
  '{name} has unsaved changes.': 'В {name} есть несохранённые изменения.',
  'Wrap': 'Переносить',
  'Unwrap': 'Не переносить',
  'Wrap long lines in the editor': 'Переносить длинные строки в редакторе',
  'Wrap: On': 'Перенос строк: включён',
  'Wrap: Off': 'Перенос строк: выключен',
  'Line Num': 'Номера',
  'Show line numbers in the editor': 'Показывать номера строк в редакторе',
  'Show line numbers: On': 'Номера строк: показаны',
  'Show line numbers: Off': 'Номера строк: скрыты',

  // Открытие.
  'Opening {name}…': 'Открывается {name}…',
  'Reading {name}…': 'Чтение {name}…',
  'Checking {name}…': 'Проверка {name}…',
  'File is too large: {size}, limit is {limit}': 'Файл слишком велик: {size}, предел — {limit}',
  'Not a UTF-8 text file: {name}': 'Это не текст в UTF-8: {name}',
  'Read-only file': 'Файл только для чтения',
  '{path} cannot be written. Open it for reading?': 'В {path} нельзя записать. Открыть на чтение?',
  '{path} cannot be written.\nOpen it for reading, or edit it anyway and save as administrator?':
      'В {path} нельзя записать.\nОткрыть на чтение или всё-таки править и сохранить от администратора?',
  'Open read-only': 'Только читать',
  'Edit anyway': 'Всё равно править',

  // Настройки.
  'Wrap long lines': 'Переносить длинные строки',
  'Show line numbers': 'Показывать номера строк',
  'Largest file to open': 'Наибольший открываемый файл',
  'bytes': 'байт',
};
