import 'package:fc_api/fc_api.dart';

import 'editor_commands.dart';
import 'editor_screen.dart';
import 'editor_settings.dart';

/// Редактор текста.
///
/// Третий экран приложения — и первый, которому фокус нужен по-настоящему:
/// печатать командами нельзя. Всё остальное устроено как у просмотрщика:
/// клавиша принадлежит экрану, ряд кнопок показывает его команды.
class TextEditor implements FcModule {
  const TextEditor();

  @override
  String get id => 'fc.editor';

  @override
  String get title => 'Text editor';

  @override
  void install(FcRegistry registry) {
    EditorSettings settingsOf() => registry.settings.section(EditorSettings.new);

    // `F4` уже закреплена оболочкой за этим идентификатором — команда занимает
    // место заглушки.
    registry.command((context) => EditFileCommand(settings: settingsOf(), onSettingsChanged: registry.settings.save));

    registry.command((context) => SaveFileCommand());
    registry.command((context) => CloseEditorCommand());
    registry.command((context) => ToggleEditorWrapCommand());

    registry.binding(KeyBinding('F2', SaveFileCommand.commandId, screen: EditorScreen.screenId));
    registry.binding(KeyBinding('Esc', CloseEditorCommand.commandId, screen: EditorScreen.screenId));
    registry.binding(KeyBinding('F10', CloseEditorCommand.commandId, screen: EditorScreen.screenId));
    registry.binding(KeyBinding('Cmd-S', SaveFileCommand.commandId, screen: EditorScreen.screenId));
    registry.binding(KeyBinding('Cmd-W', ToggleEditorWrapCommand.commandId, screen: EditorScreen.screenId));
  }
}
