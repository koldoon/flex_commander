import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logecom/logecom.dart';

import 'app.dart';
import 'bootstrap/app_modules.dart';
import 'bootstrap/bootstrap.dart';
import 'modules/local_fs/plugin_window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginWindowService.ensureInitialized();

  _setUpLogging();

  // Единственное место в ядре, которое знает модули по именам. Всё остальное
  // работает с тем, что модули объявили, и не подозревает об их существовании.
  final runtime = await initModules(appModules());

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

  final logger = Logecom.createLogger('App');
  FlutterError.onError = (details) => logger.error('Flutter error', [details.exception, details.stack]);
}
