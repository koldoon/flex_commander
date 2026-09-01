import 'package:fc_7z/fc_7z.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:fc_tar/fc_tar.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:fc_zip/fc_zip.dart';

import '../modules/app_shell.dart';
import '../modules/dnd/system_drag_and_drop.dart';
import 'package:fc_local_fs/fc_local_fs.dart';

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
  // Панели — обычный модуль: ядро показывает верхний экран и ряд кнопок, а чем
  // показывать файлы, решает он.
  const Panels(),
  // Терминал раньше навигации: в режиме `mc` печать перехватывает он, а
  // выигрывает та привязка, что объявлена раньше. Выключен режим — команды
  // строки невыполнимы, и клавиша достаётся навигации, как раньше.
  ShellTerminal(),
  // Поиск раньше навигации: в списке находок `Enter` ведёт к файлу в его
  // каталоге, а не открывает его, и выигрывает та привязка, что объявлена
  // раньше. Вне находок команда невыполнима, и `Enter` достаётся навигации.
  const FileSearch(),
  const Navigation(),
  const FileOps(),
  // Перетаскивание мышью. Платформенного в дартовой части нет — только имя
  // канала; без своего раннера канал молчит, и это ровно «перетаскивания нет».
  const SystemDragAndDrop(),
  const ZipArchiver(),
  const SevenZipArchiver(),
  const TarArchiver(),
  const SshFileSystem(),
  // Оболочка просмотра занимает место заглушки на F3; просмотрщики объявляют
  // себя ей в реестр. Первая выбирает, вторые показывают.
  const Viewer(),
  const TextViewer(),
  const ImageViewer(),
  // Последним в очереди просмотрщиков: берётся за то, за что не взялся никто.
  const FileInfo(),
  // Редактор после оболочки: он занимает место её заглушки на F4.
  const TextEditor(),
];
