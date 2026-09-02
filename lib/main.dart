import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:flutter/widgets.dart';
import 'package:logecom/logecom.dart';

import 'app.dart';
import 'bootstrap/app_modules.dart';
import 'bootstrap/bootstrap.dart';
import 'bootstrap/error_traps.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginWindowService.ensureInitialized();

  _setUpLogging();

  // Ловушки ставятся до всего остального: поломка при запуске — тоже поломка,
  // и терять её нельзя. Пока приложения нет, пойманное копится и уходит
  // сборщику, как только тот появится.
  final logger = Logecom.createLogger('App');
  final traps = ErrorTraps(log: (error, stack) => logger.error('Unhandled', [error, stack]))..install();

  // Единственное место в ядре, которое знает модули по именам. Всё остальное
  // работает с тем, что модули объявили, и не подозревает об их существовании.
  final runtime = await initModules(backendModules(), frontendModules());
  traps.attach(runtime.app.errors);

  runApp(FlexCommanderApp(controller: runtime.app));

  // Окно и каталоги восстанавливаются уже после первого кадра: окно
  // показывается сразу с сохранёнными размерами, а панели заполняются
  // по мере чтения.
  unawaited(runtime.app.start());
}

void _setUpLogging() {
  Logecom.instance.pipeline = [
    ConsoleTransport(
      printingMethod: kDebugMode ? PrintingMethod.stdOut : PrintingMethod.developerLog,
      alignMessages: true,
    ),
  ];
}
