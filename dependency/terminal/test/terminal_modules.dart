import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';

/// Приложение с подставным псевдотерминалом — **на том же месте**, где стоит
/// настоящий модуль.
///
/// Место существенно: терминал объявлен раньше навигации, и на этом держится
/// перехват печати в режиме `mc`. Добавь его в конец списка — и буква снова
/// уйдёт в переход к имени, а тест покажет то, чего в приложении нет.
List<FcModule> modulesWithTerminal(FakePty pty) => [
  for (final module in featureModules())
    if (module.id == 'fc.terminal') ShellTerminal(pty: pty) else module,
];
