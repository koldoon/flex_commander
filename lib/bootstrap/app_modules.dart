import 'package:fc_7z_archiver/fc_7z_archiver.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_zip_archiver/fc_zip_archiver.dart';

import '../modules/app_shell.dart';
import '../modules/local_fs/local_file_system.dart';

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
  const DefaultTheme(),
  const Navigation(),
  const FileOps(),
  const ZipArchiver(),
  const SevenZipArchiver(),
];
