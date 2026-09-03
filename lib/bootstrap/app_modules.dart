import 'package:fc_7z/backend.dart';
import 'package:fc_7z/frontend.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_editor/backend.dart';
import 'package:fc_editor/frontend.dart';
import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_local_fs/backend.dart';
import 'package:fc_local_fs/frontend.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:fc_tar/backend.dart';
import 'package:fc_tar/frontend.dart';
import 'package:fc_terminal/backend.dart';
import 'package:fc_terminal/frontend.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:fc_zip/backend.dart';
import 'package:fc_zip/frontend.dart';

import '../modules/app_shell_backend.dart';
import '../modules/app_shell_frontend.dart';
import '../modules/dnd/system_drag_and_drop.dart';

/// Из чего собрано ядро.
///
/// Списка два, по одному на сторону, и это не удвоение, а сама граница:
/// читая их, видно, из чего собрана каждая половина приложения. Модуль,
/// у которого есть и то и другое, стоит в обоих — разными классами из разных
/// библиотек (`docs/spec/client-server.md`, §8).
///
/// Порядок в ядре ни на что не влияет: приоритет задают привязки клавиш, а их
/// здесь нет вовсе.
List<FcBackendModule> backendModules() => [
  const LocalFileSystemBackend(),
  const AppShellBackend(),
  ...featureBackendModules(),
];

/// Ядровые половины модулей без платформенных.
///
/// Тем же списком пользуются тесты: приложение они собирают на подставном
/// дереве, а источники архивов и оболочка должны быть теми же, что и в
/// настоящем запуске, — иначе команда упаковки не найдёт своей службы.
List<FcBackendModule> featureBackendModules() => [
  const ShellTerminalBackend(),
  const TextEditorBackend(),
  const ZipArchiverBackend(),
  const SevenZipArchiverBackend(),
  const TarArchiverBackend(),
  const SshFileSystem(),
];

/// Из чего собран интерфейс.
///
/// Порядок важен: им задаётся приоритет привязок клавиш.
List<FcFrontendModule> frontendModules() => [const LocalFileSystemFrontend(), ...featureModules()];

/// Экранные модули без платформенных.
///
/// Тесты собирают приложение на подставном дереве и подставном окне, поэтому
/// экранная половина модуля локальной файловой системы им не нужна — а вот всё
/// остальное должно быть тем же, что и в настоящем запуске.
List<FcFrontendModule> featureModules() => [
  const AppShellFrontend(),
  const DefaultTheme(),
  // Панели — обычный модуль: ядро показывает верхний экран и ряд кнопок, а чем
  // показывать файлы, решает он.
  const Panels(),
  // Терминал раньше навигации: в режиме `mc` печать перехватывает он, а
  // выигрывает та привязка, что объявлена раньше. Выключен режим — команды
  // строки невыполнимы, и клавиша достаётся навигации, как раньше.
  ShellTerminalFrontend(),
  // Поиск раньше навигации: в списке находок `Enter` ведёт к файлу в его
  // каталоге, а не открывает его, и выигрывает та привязка, что объявлена
  // раньше. Вне находок команда невыполнима, и `Enter` достаётся навигации.
  const FileSearch(),
  const Navigation(),
  const FileOps(),
  // Перетаскивание мышью. Платформенного в дартовой части нет — только имя
  // канала; без своего раннера канал молчит, и это ровно «перетаскивания нет».
  const SystemDragAndDrop(),
  const ZipArchiverFrontend(),
  const SevenZipArchiverFrontend(),
  const TarArchiverFrontend(),
  // Оболочка просмотра занимает место заглушки на F3; просмотрщики объявляют
  // себя ей в реестр. Первая выбирает, вторые показывают.
  const Viewer(),
  const TextViewer(),
  const ImageViewer(),
  // Последним в очереди просмотрщиков: берётся за то, за что не взялся никто.
  const FileInfo(),
  // Редактор после оболочки: он занимает место её заглушки на F4.
  const TextEditorFrontend(),
];
