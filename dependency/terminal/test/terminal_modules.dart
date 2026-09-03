import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';

/// Приложение с настоящим набором модулей.
///
/// Подставного псевдотерминала здесь больше нет: оболочку даёт **провайдер**
/// (`InMemoryShellProvider`), а не служба, и подменять модуль ради неё не
/// нужно. Порядок модулей при этом важен по-прежнему: терминал объявлен раньше
/// навигации, и на этом держится перехват печати в режиме `mc`.
List<FcModule> modulesWithTerminal() => featureModules();
