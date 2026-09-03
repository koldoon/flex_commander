import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';

import 'editor_commands.dart';
import 'editor_screen.dart';
import 'editor_settings.dart';
import 'editor_view.dart';

/// Редактор текста.
///
/// Третий экран приложения — и первый, которому фокус нужен по-настоящему:
/// печатать командами нельзя. Всё остальное устроено как у просмотрщика:
/// клавиша принадлежит экрану, ряд кнопок показывает его команды.
class TextEditorFrontend implements FcFrontendModule {
  const TextEditorFrontend();

  /// Поиск: команды общие с просмотрщиком, идентификаторы свои.
  static const String findCommandId = 'editor.find';
  static const String findNextCommandId = 'editor.findNext';
  static const String findPreviousCommandId = 'editor.findPrevious';

  @override
  String get id => 'fc.editor';

  @override
  String get title => 'Text editor';

  @override
  void installFrontend(FrontendRegistry registry) {
    // Что рисует состояние, объявляет тот же модуль, который его завёл.
    registry.view<EditorScreen>((context, state) => EditorView(screen: state));
    // Область забирается **сейчас**, пока идёт установка: позже имя раздела
    // уже неизвестно, и настройки уехали бы в чужой.
    final settings = registry.settings;
    EditorSettings settingsOf() => settings.section(EditorSettings.new);

    // `F4` уже закреплена оболочкой за этим идентификатором — команда занимает
    // место заглушки.
    registry.settingsSchema(
      () => SettingsSchema([
        SettingsField.flag(
          'wordWrap',
          defaultValue: false,
          title: 'Wrap long lines',
          read: () => settingsOf().wordWrap,
          write: (value) => settingsOf().wordWrap = value,
        ),
        SettingsField.flag(
          'showLineNumbers',
          defaultValue: true,
          title: 'Show line numbers',
          read: () => settingsOf().showLineNumbers,
          write: (value) => settingsOf().showLineNumbers = value,
        ),
        SettingsField.integer(
          'maxFileSize',
          defaultValue: EditorSettings.defaultMaxFileSize,
          title: 'Largest file to open',
          unit: 'bytes',
          min: 1024,
          max: 100 * 1024 * 1024,
          read: () => settingsOf().maxFileSize,
          write: (value) => settingsOf().maxFileSize = value,
        ),
      ], save: settings.save),
    );

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
