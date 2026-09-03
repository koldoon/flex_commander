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

  // Единственное место, которое знает модули по именам. Всё остальное работает
  // с тем, что модули объявили, и не подозревает об их существовании.
  //
  // Где живёт ядро — здесь и решается, и это ровно одна строка: в изоляте
  // (`initIsolated`) или в этом же (`initModules`). Всё остальное о выборе не
  // знает: разница между портом и петлёй кончается на сборке интерфейса
  // (`docs/spec/client-server.md`, §10).
  final runtime =
      _isolatedCore ? await initIsolated(frontendModules()) : await initModules(backendModules(), frontendModules());
  traps.attach(runtime.app.errors);

  runApp(FlexCommanderApp(controller: runtime.app));

  // Окно и каталоги восстанавливаются уже после первого кадра: окно
  // показывается сразу с сохранёнными размерами, а панели заполняются
  // по мере чтения.
  unawaited(runtime.app.start());
}

/// Поднимать ли ядро отдельным изолятом. По умолчанию — да.
///
/// Переменной сборки, а не настройкой: выбор делается один раз при запуске, и
/// менять его на ходу нечему — с ним меняется всё, что ядро держит.
///
/// Изолят и есть то, ради чего всё затевалось: тяжёлая работа перестаёт
/// отнимать кадры у показа. Замер это подтвердил — пауза цикла событий на
/// поиске 6.5–9.3 мс против 14–36 на петле, то есть кадр не пропускается вовсе
/// (`docs/spec/client-server.md`, §10.1).
///
/// Петля остаётся и никуда не денется: на ней идёт весь прогон, и она же —
/// запасной путь, если с портом что-то окажется не так. Собрать с ней:
/// `--dart-define=FC_ISOLATED_CORE=false`.
const bool _isolatedCore = bool.fromEnvironment('FC_ISOLATED_CORE', defaultValue: true);

void _setUpLogging() {
  Logecom.instance.pipeline = [
    ConsoleTransport(
      printingMethod: kDebugMode ? PrintingMethod.stdOut : PrintingMethod.developerLog,
      alignMessages: true,
    ),
  ];
}
