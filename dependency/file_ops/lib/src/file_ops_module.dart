import 'package:fc_api/fc_api.dart';

import 'file_commands.dart';
import 'transfer_commands.dart';

/// Файловые операции: создать каталог, удалить, скопировать, перенести.
///
/// Всё, ради чего файловый менеджер и заводят. Отдельным модулем — по той же
/// причине, что и навигация: это набор действий, а не устройство приложения.
/// Работают они через [TreeEditor], поэтому источник и приёмник могут быть
/// из разных провайдеров, и модулю это безразлично.
class FileOps implements FcModule {
  const FileOps();

  @override
  String get id => 'fc.file_ops';

  @override
  String get title => 'File operations';

  @override
  void install(FcRegistrar registrar) {
    registrar.command((context) => MakeDirectoryCommand());
    registrar.command((context) => RemoveCommand());
    registrar.command((context) => RemovePermanentlyCommand());
    registrar.command((context) => CopyCommand());
    registrar.command((context) => MoveCommand());

    registrar.binding(KeyBinding('F5', 'file.copy'));
    registrar.binding(KeyBinding('F6', 'file.move'));
    registrar.binding(KeyBinding('F7', 'file.mkdir'));
    // На macOS F-клавиши по умолчанию отданы системе (F7 — «предыдущий трек»),
    // и до приложения нажатие не доходит. Привычное сочетание из Finder
    // работает без настройки клавиатуры.
    registrar.binding(KeyBinding('Shift-Cmd-N', 'file.mkdir'));
    registrar.binding(KeyBinding('F8', 'file.remove'));
    registrar.binding(KeyBinding('Shift-F8', 'file.removePermanently'));
    registrar.binding(KeyBinding('Cmd-Bsp', 'file.remove'));
    registrar.binding(KeyBinding('Shift-Cmd-Bsp', 'file.removePermanently'));
  }
}
