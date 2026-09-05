import 'package:fc_7z/fc_7z.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
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

/// Из чего собрано приложение.
///
/// Список один, а сторон две: у какого модуля какая половина, знает он сам —
/// объявляет `FcBackendModule`, `FcFrontendModule` или оба сразу. Сборка
/// разбирает список по типам ([backendModules], [frontendModules]), и второго
/// перечисления держать не приходится: модуль в двух списках однажды уже
/// разъезжался с самим собой (`docs/modules.md`).
///
/// Порядок важен: им задаётся приоритет привязок клавиш. На ядровую половину
/// он не влияет — привязок там нет вовсе.
List<FcModule> appModules() => [const LocalFileSystem(), ...featureModules()];

/// Модули без платформенных.
///
/// Тем же списком пользуются тесты: дерево и окно у них подставные, а всё
/// остальное должно быть тем же, что и в настоящем запуске, — иначе команда
/// упаковки не найдёт своей службы.
List<FcModule> featureModules() => [
  const AppShell(),
  const DefaultTheme(),
  // Панели — обычный модуль: оболочка показывает верхний экран и ряд кнопок, а
  // чем показывать файлы, решает он.
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
  // Тип по содержимому: службу спрашивает показ, а модуль не приносит ни
  // колонки, ни команды — только ответ на вопрос «что это за файл».
  const ContentTypeDetection(),
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

/// Ядровые половины — те модули из списка, у которых она есть.
List<FcBackendModule> backendModules() => appModules().whereType<FcBackendModule>().toList();

/// Экранные половины — так же.
List<FcFrontendModule> frontendModules() => appModules().whereType<FcFrontendModule>().toList();
