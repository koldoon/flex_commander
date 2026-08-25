import 'package:fc_api/fc_api.dart';
import 'package:fc_text_kit/fc_text_kit.dart';

import 'viewer_commands.dart';
import 'viewer_screen.dart';
import 'viewer_settings.dart';
import 'viewer_view.dart';

/// Просмотрщик текста.
///
/// Второй экран приложения после файловых панелей — и первый, ради которого
/// понятие экрана заводилось: он занимает место панелей, оставляет ряд
/// функциональных кнопок и переназначает его на свои команды.
class TextViewer implements FcModule {
  const TextViewer();

  /// Поиск: команды общие, а идентификаторы свои — в панелях за `F7` стоит
  /// своя команда, и путать их незачем.
  static const String findCommandId = 'viewer.find';
  static const String findNextCommandId = 'viewer.findNext';
  static const String findPreviousCommandId = 'viewer.findPrevious';

  @override
  String get id => 'fc.viewer';

  @override
  String get title => 'Text viewer';

  @override
  void install(FcRegistry registry) {
    // Что рисует состояние, объявляет тот же модуль, который его завёл.
    registry.view<ViewerScreen>((context, state) => ViewerView(screen: state));
    // Раздел настроек читается не сейчас, а когда позовут фабрику: во время
    // объявления настроек ещё нет.
    ViewerSettings settingsOf() => registry.settings.section(ViewerSettings.new);

    // Клавиша `F3` уже закреплена оболочкой за этим идентификатором — команда
    // просто занимает место заглушки.
    registry.command((context) => ViewFileCommand(settings: settingsOf(), onSettingsChanged: registry.settings.save));

    registry.command((context) => ToggleWordWrapCommand());
    registry.command((context) => CloseViewerCommand());
    registry.command((context) => ToggleViewerNumbersCommand());
    registry.command((context) => CopySelectionCommand(registry.services.resolve<ClipboardService>()));

    // Поиск — общий с редактором: экран и идентификаторы приходят отсюда, а
    // сами команды одни на двоих (`fc_text_kit`).
    registry.command((context) => FcFindTextCommand(id: findCommandId, screenId: ViewerScreen.screenId));
    registry.command((context) => FcFindNextCommand(id: findNextCommandId, screenId: ViewerScreen.screenId));
    registry.command((context) => FcFindPreviousCommand(id: findPreviousCommandId, screenId: ViewerScreen.screenId));

    // Привязки просмотрщика действуют только в его экране: в панелях за этими
    // же клавишами стоят свои команды, и ряд кнопок показывает те, что сейчас
    // на месте.
    registry.binding(KeyBinding.inState<ViewerScreen>('F2', ToggleWordWrapCommand.commandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('Esc', CloseViewerCommand.commandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('F10', CloseViewerCommand.commandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('F7', findCommandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('Cmd-F', findCommandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('Shift-F7', findNextCommandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('Cmd-G', findNextCommandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('Shift-Cmd-G', findPreviousCommandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('F9', ToggleViewerNumbersCommand.commandId));
    registry.binding(KeyBinding.inState<ViewerScreen>('Cmd-C', CopySelectionCommand.commandId));

    // Стрелок, страниц и `Home` здесь нет нарочно: прокрутку и выделение
    // забрал себе показ — он же берёт фокус. Пока просмотрщик рисовал строки
    // сам, это были команды; общий с редактором показ сделал их его делом.
  }
}
