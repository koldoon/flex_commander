import 'package:fc_7z/fc_7z.dart';
import 'package:fc_archive/fc_archive.dart';
import 'package:fc_attributes/fc_attributes.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:fc_file_info/fc_file_info.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_json/fc_json.dart';
import 'package:fc_mermaid/fc_mermaid.dart';
import 'package:fc_key_presets/fc_key_presets.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_places/fc_places.dart';
import 'package:fc_s3/fc_s3.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:fc_tar/fc_tar.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_updater/fc_updater.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:fc_zip/fc_zip.dart';

import '../modules/app_shell.dart';
import '../modules/clipboard/system_file_clipboard.dart';
import '../modules/dnd/system_drag_and_drop.dart';
import '../modules/accent/system_accent.dart';
import '../modules/fonts/system_fonts.dart';
import '../modules/icons/system_icons.dart';
import '../modules/images/system_images.dart';
import '../modules/pdf/system_pdf.dart';
import '../modules/video/system_video.dart';

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
  // Правка оформления — отдельным модулем рядом с темой: выключили его, и темы
  // остались, а править их нечем (`docs/spec/theme-editor.md`, §2).
  const ThemeEditing(),
  // Терминал раньше панелей и навигации: в режиме `mc` печать перехватывает он,
  // а выигрывает та привязка, что объявлена раньше. Выключен режим или пуста
  // строка — команды строки невыполнимы, и клавиша достаётся тому, кто следом:
  // раскрытию ветви в дереве, переходу к имени, входу в каталог.
  //
  // Раньше панелей он оказался не сразу: `Enter` над ветвью дерева раскрывал
  // её, хотя в строке уже было набрано, — и набранное не выполнялось вовсе.
  ShellTerminal(),
  // Панели — обычный модуль: оболочка показывает верхний экран и ряд кнопок, а
  // чем показывать файлы, решает он.
  const Panels(),
  // Поиск раньше навигации: в списке находок `Enter` ведёт к файлу в его
  // каталоге, а не открывает его, и выигрывает та привязка, что объявлена
  // раньше. Вне находок команда невыполнима, и `Enter` достаётся навигации.
  const FileSearch(),
  const Navigation(),
  // Боковая полоса избранного: места слева от панелей. Клавиши у неё свои и
  // действуют, только пока ввод у неё, — порядок ей не важен.
  const Places(),
  const FileOps(),
  // Перетаскивание мышью. Платформенного в дартовой части нет — только имя
  // канала; без своего раннера канал молчит, и это ровно «перетаскивания нет».
  const SystemDragAndDrop(),
  // Файлы в буфере обмена — тем же способом и по той же причине: буфер файлов
  // знает только система (`docs/spec/file-clipboard.md`).
  const FileClipboardModule(),
  // Тип по содержимому: службу спрашивает показ, а модуль не приносит ни
  // колонки, ни команды — только ответ на вопрос «что это за файл».
  const ContentTypeDetection(),
  // Иконки строк по правилам. Стоит после типов и значков системы не по
  // необходимости — службы разбираются лениво, — а потому что читается сверху
  // вниз: сперва то, что он спрашивает, потом он сам.
  const SystemFileIcons(),
  // Перечень установленных шрифтов: из Flutter его не узнать, а редактору тем
  // он нужен, чтобы предлагать шрифт списком, а не заставлять набирать имя
  // (`docs/spec/theme-editor.md`, §12).
  const SystemFontList(),
  // Акцентный цвет системы: им оформления macOS красят выделение, кнопку по
  // умолчанию и обводку фокуса. Канал двусторонний — акцент меняют на ходу
  // (`docs/spec/macos-themes.md`, §5).
  const SystemAccentColor(),
  // Разбор картинок, которых не умеет Flutter: `HEIC` и всё, что читает
  // система, а Skia — нет. Просмотрщик спрашивает его последним, когда свой
  // разбор не справился (`docs/spec/image-viewer.md`, §12).
  const SystemImageDecoding(),
  // PDF силами системы: документ держит раннер, просмотрщик просит нарисовать
  // видимые страницы (`docs/spec/pdf-viewer.md`, §3).
  const SystemPdfRendering(),
  // Видео силами системы: плеер держит раннер, кадры идут в текстуру
  // (`docs/spec/video-viewer.md`, §3).
  const SystemVideoPlayback(),
  const FileIconRules(),
  const ZipArchiver(),
  const SevenZipArchiver(),
  const TarArchiver(),
  // Архив по месту: форматов не знает — берёт то, что объявили модули выше
  // (`docs/spec/archive-here.md`).
  const ArchiveHere(),
  const SshFileSystem(),
  // Второй источник по адресу. Свой клиент на dart:io: у дартовых пакетов
  // канал данных при FTPS не шифруется, а сертификат принимается любой
  // (`docs/spec/ftp.md`, §8).
  const FtpFileSystem(),
  // Третий источник по адресу — хранилища S3. Клиент свой, на dart:io, с
  // подписью SigV4; соединение — в адресе, как у ssh и ftp
  // (`docs/spec/s3.md`, §5).
  const S3FileSystem(),
  // Оболочка просмотра занимает место заглушки на F3; просмотрщики объявляют
  // себя ей в реестр. Первая выбирает, вторые показывают.
  const Viewer(),
  const TextViewer(),
  const ImageViewer(),
  const PdfViewer(),
  const MarkdownViewer(),
  // Диаграммы — не просмотрщик, а рисовальщик врезки внутри документа: он
  // объявляет себя в реестр из Г19 и о markdown больше ничего не знает.
  const Mermaid(),
  const JsonFormatting(),
  const KeyPresets(),
  // Последним в очереди просмотрщиков: берётся за то, за что не взялся никто.
  const FileInfo(),
  // Правка того, что сведения показывают: права, даты, владелец, xattr.
  const AttributeEditing(),
  // Редактор после оболочки: он занимает место её заглушки на F4.
  const TextEditor(),
  // История работ — после всех, чьи работы она записывает: порядок здесь
  // задаёт лишь приоритет привязок, а `Cmd-Z` не спорит ни с кем
  // (`docs/spec/operation-history.md`).
  const OperationHistoryModule(),
  // Обновление приложения собой же. Последним: оно ни от чего не зависит и
  // ничего не приносит панелям — только команду, окно и флажок в настройках
  // (`docs/spec/self-update.md`).
  const Updates(),
];

/// Ядровые половины — те модули из списка, у которых она есть.
List<FcBackendModule> backendModules() => appModules().whereType<FcBackendModule>().toList();

/// Экранные половины — так же.
List<FcFrontendModule> frontendModules() => appModules().whereType<FcFrontendModule>().toList();
