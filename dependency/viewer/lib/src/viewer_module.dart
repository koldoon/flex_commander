import 'package:fc_api/fc_api.dart';

import 'viewer_commands.dart';
import 'viewer_screen.dart';
import 'viewer_settings.dart';

/// Просмотрщик текста.
///
/// Второй экран приложения после файловых панелей — и первый, ради которого
/// понятие экрана заводилось: он занимает место панелей, оставляет ряд
/// функциональных кнопок и переназначает его на свои команды.
class TextViewer implements FcModule {
  const TextViewer();

  @override
  String get id => 'fc.viewer';

  @override
  String get title => 'Text viewer';

  @override
  void install(FcRegistry registry) {
    // Раздел настроек читается не сейчас, а когда позовут фабрику: во время
    // объявления настроек ещё нет.
    ViewerSettings settingsOf() => registry.settings.section(ViewerSettings.new);

    // Клавиша `F3` уже закреплена оболочкой за этим идентификатором — команда
    // просто занимает место заглушки.
    registry.command((context) => ViewFileCommand(settings: settingsOf(), onSettingsChanged: registry.settings.save));

    registry.command((context) => ToggleWordWrapCommand());
    registry.command((context) => CloseViewerCommand());
    registry.command((context) => ScrollViewerCommand());
    registry.command((context) => CopySelectionCommand(registry.services.resolve<ClipboardService>()));

    // Привязки просмотрщика действуют только в его экране: в панелях за этими
    // же клавишами стоят свои команды, и ряд кнопок показывает те, что сейчас
    // на месте.
    registry.binding(KeyBinding('F2', ToggleWordWrapCommand.commandId, screen: ViewerScreen.screenId));
    registry.binding(KeyBinding('Esc', CloseViewerCommand.commandId, screen: ViewerScreen.screenId));
    registry.binding(KeyBinding('F10', CloseViewerCommand.commandId, screen: ViewerScreen.screenId));
    registry.binding(KeyBinding('Cmd-C', CopySelectionCommand.commandId, screen: ViewerScreen.screenId));

    // Прокрутка — такие же команды, как всё остальное: клавиша принадлежит
    // экрану, и переназначить её можно будет из настроек. Куда двигать,
    // приходит значением привязки.
    for (final entry
        in const {
          'Up': ScrollStep.lineUp,
          'Down': ScrollStep.lineDown,
          'PgUp': ScrollStep.pageUp,
          'PgDn': ScrollStep.pageDown,
          'Home': ScrollStep.toStart,
          'End': ScrollStep.toEnd,
          'Left': ScrollStep.columnLeft,
          'Right': ScrollStep.columnRight,
        }.entries) {
      registry.binding(
        KeyBinding(
          entry.key,
          ScrollViewerCommand.commandId,
          screen: ViewerScreen.screenId,
          parameters: {ScrollViewerCommand.stepParam: entry.value.name},
        ),
      );
    }
  }
}
