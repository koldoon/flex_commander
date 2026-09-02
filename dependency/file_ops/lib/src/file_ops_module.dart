import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'file_commands.dart';
import 'transfer_commands.dart';

/// Файловые операции: создать каталог, удалить, скопировать, перенести.
///
/// Всё, ради чего файловый менеджер и заводят. Отдельным модулем — по той же
/// причине, что и навигация: это набор действий, а не устройство приложения.
/// Работают они через [TreeEditor], поэтому источник и приёмник могут быть
/// из разных провайдеров, и модулю это безразлично.
class FileOps implements FcFrontendModule {
  const FileOps();

  static const String commandId = 'fc.file_ops';

  @override
  String get id => commandId;

  @override
  String get title => 'File operations';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.command((context) => MakeDirectoryCommand());
    registry.command((context) => RenameCommand());
    registry.command((context) => RemoveCommand());
    registry.command((context) => RemovePermanentlyCommand());
    registry.command((context) => CopyCommand());
    registry.command((context) => MoveCommand());

    registry.binding(KeyBinding('F5', CopyCommand.commandId));
    registry.binding(KeyBinding('F6', MoveCommand.commandId));
    registry.binding(KeyBinding('F7', MakeDirectoryCommand.commandId));
    // Shift-F6 — там же, где переименование во всех коммандерах: рядом с
    // переносом, потому что это его ближайший родственник.
    registry.binding(KeyBinding('Shift-F6', RenameCommand.commandId));
    // На macOS F-клавиши по умолчанию отданы системе (F7 — «предыдущий трек»),
    // и до приложения нажатие не доходит. Привычное сочетание из Finder
    // работает без настройки клавиатуры.
    registry.binding(KeyBinding('Shift-Cmd-N', MakeDirectoryCommand.commandId));
    registry.binding(KeyBinding('F8', RemoveCommand.commandId));
    registry.binding(KeyBinding('Shift-F8', RemovePermanentlyCommand.commandId));
    registry.binding(KeyBinding('Cmd-Bsp', RemoveCommand.commandId));
    registry.binding(KeyBinding('Shift-Cmd-Bsp', RemovePermanentlyCommand.commandId));
  }
}
