/// Командный фреймворк: команда, составные команды и то, чем они обмениваются.
///
/// Порт ядра [Spicelib-Commands](https://github.com/spicefactory/Spicelib-Commands)
/// на Dart. Ветвления по итогу шага (`CommandFlow` со связями и условиями) не
/// портированы: в файловом менеджере таких сценариев пока нет, а каркас под
/// несуществующую нагрузку — это код, который никто не проверяет.
library;

export 'command.dart';
export 'command_data.dart';
export 'command_executor.dart';
export 'command_group.dart';
export 'command_lifecycle.dart';
export 'command_proxy.dart';
export 'commands.dart';
export 'util_commands.dart';
