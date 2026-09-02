import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';

/// Приложение с настоящим набором модулей.
///
/// Подставного псевдотерминала здесь больше нет: оболочку даёт **провайдер**
/// (`InMemoryShellProvider`), а не служба, и подменять модуль ради неё не
/// нужно. Порядок модулей при этом важен по-прежнему: терминал объявлен раньше
/// навигации, и на этом держится перехват печати в режиме `mc`.
List<FcFrontendModule> modulesWithTerminal() => featureModules();
