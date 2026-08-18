import 'package:fc_api/fc_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';

import '../modules/app_shell.dart';
import '../modules/legacy_commands.dart';
import '../modules/local_fs/local_file_system.dart';
import '../modules/zip/zip_module.dart';

/// Из чего собрано приложение.
///
/// Единственный список модулей в ядре. Порядок важен: им задаётся приоритет
/// привязок клавиш, а платформенное идёт первым — от него зависят остальные.
List<FcModule> appModules() => [const LocalFileSystem(), ...featureModules()];

/// Модули без платформенных.
///
/// Тесты собирают приложение на подставном дереве и подставном окне, поэтому
/// модуль локальной файловой системы им не нужен — а вот всё остальное должно
/// быть тем же, что и в настоящем запуске.
List<FcModule> featureModules() => [
  const AppShell(),
  const Navigation(),
  const FileOps(),
  const LegacyCommands(),
  const ZipArchiver(),
];
