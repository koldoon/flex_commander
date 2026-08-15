import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logecom/logecom.dart';

import 'app.dart';
import 'app_context.dart';
import 'model/os/plugin_window_service.dart';
import 'state/app_controller.dart';
import 'view/dialogs/dialog_user_interaction.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginWindowService.ensureInitialized();

  _setUpLogging();

  // Все службы создаёт контейнер: здесь только точка сборки.
  final context = await AppContext.init();
  final controller = context.get<AppController>();
  final dialogs = context.get<DialogUserInteraction>();

  runApp(FlexCommanderApp(controller: controller, navigatorKey: dialogs.navigatorKey));

  // Окно и каталоги восстанавливаются уже после первого кадра: окно
  // показывается сразу с сохранёнными размерами, а панели заполняются
  // по мере чтения.
  unawaited(controller.start());
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
