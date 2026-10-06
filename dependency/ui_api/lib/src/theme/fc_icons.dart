import 'package:flutter/widgets.dart';

/// Иконки приложения — глифы шрифта, а не картинки.
///
/// Рисуются как текст: в референсе (`resources/styles/icon.as`) иконка была
/// обычной меткой со шрифтом `icon_cff`. Отсюда и [fontFamily] — им же
/// красится и масштабируется всё остальное.
///
/// Здесь только роли: какая иконка что означает. Сами глифы и шрифт приносит
/// тема — так же, как цвета и размеры.
abstract class FcIcons {
  const FcIcons();

  /// Шрифт, из которого берутся глифы.
  String get fontFamily;

  IconData get folder;

  /// Лист бумаги — обычный файл.
  ///
  /// В строке списка у него значка нет вовсе (так было в референсе), и это
  /// читается отступом. А в плитке сетки значков пустое место — дыра, и рисует
  /// её она (`docs/spec/panel-view-icons.md`, §4).
  IconData get file;

  IconData get folderOpen;

  IconData get link;

  IconData get asterisk;

  IconData get check;

  /// Смешанное состояние флажка: «у выбранных по-разному, не трогать».
  ///
  /// Чёрточка, а не половина галочки и не серый квадрат: галочка означала бы
  /// «да, но слабее», квадрат — «нельзя». Чёрточка не обещает ни того, ни
  /// другого, и её же рисуют системы, у которых такой флажок есть.
  IconData get mixed;

  /// Стрелка «туда, откуда пришли» — «назад» в шапке панели
  /// (`docs/spec/session-history.md`, §9).
  IconData get angleLeft;

  /// Стрелка «ведёт на» — в описании ссылки.
  ///
  /// Не `long-arrow-right`: та почти целую кегельную площадку в ширину
  /// (0.96 em против 0.33) и рядом с именем выглядит растянутой.
  IconData get angleRight;

  /// Направление сортировки в заголовке колонки.
  IconData get caretUp;

  IconData get caretDown;

  /// Свёрнутая ветвь дерева каталогов.
  ///
  /// Шеврон, а не треугольник: залитый треугольник в дереве читается как
  /// «сюда», хотя означает «здесь есть ещё». Так же он выглядит в редакторах,
  /// откуда привычка и берётся (`docs/spec/panel-view-tree.md`, §4).
  IconData get branchClosed;

  /// Раскрытая ветвь — тот же шеврон, повёрнутый вниз.
  IconData get branchOpen;

  /// Кружок, которым в референсе **измеряли** ширину места под иконку: у
  /// обычного файла иконки нет, но колонка имён должна начинаться одинаково.
  IconData get circleOutline;

  /// Битая ссылка: в референсе такого случая не было.
  IconData get exclamation;

  // Знакомые места боковой полосы (`docs/spec/favorites-sidebar.md`, §2):
  // узнаются по адресу, а не по имени, и всё прочее — [folder].

  /// Домашний каталог.
  IconData get home;

  /// «Рабочий стол».
  IconData get desktop;

  /// «Документы».
  IconData get documents;

  /// «Загрузки».
  IconData get downloads;

  /// «Программы».
  IconData get applications;

  /// Корень и подключённые тома.
  IconData get volume;

  /// Удалённое место: `ssh://`, `ftp://`.
  IconData get server;

  /// Место внутри архива.
  IconData get archive;

  // Знаки полосы заголовка окна: рядом друг с другом, и потому из одного
  // набора и одного веса.

  /// Закрыть окно — то же, что `Esc`.
  IconData get close;

  /// Справка окна — то же, что `F1` в нём.
  IconData get help;

  // Проигрывание (`docs/spec/video-viewer.md`, §6).

  /// Пуск.
  IconData get play;

  /// Пауза.
  IconData get pause;

  /// Звук включён.
  IconData get soundOn;

  /// Звук выключен.
  IconData get soundOff;

  /// Во весь экран.
  IconData get enterFullScreen;

  /// Из полного экрана обратно.
  IconData get exitFullScreen;
}

/// Роль по имени — для правил, приехавших из файла настроек.
///
/// Имена те же, что у геттеров: `glyph:folder` в правиле иконки означает
/// [FcIcons.folder]. Незнакомое имя даёт null, и правило с ним пропускается —
/// файл настроек правят руками (`docs/spec/file-icons.md`, §4).
extension FcIconRoles on FcIcons {
  IconData? byRole(String role) => switch (role) {
    'folder' => folder,
    'file' => file,
    'folderOpen' => folderOpen,
    'link' => link,
    'asterisk' => asterisk,
    'check' => check,
    'mixed' => mixed,
    'angleLeft' => angleLeft,
    'angleRight' => angleRight,
    'caretUp' => caretUp,
    'caretDown' => caretDown,
    'branchClosed' => branchClosed,
    'branchOpen' => branchOpen,
    'circleOutline' => circleOutline,
    'exclamation' => exclamation,
    'home' => home,
    'desktop' => desktop,
    'documents' => documents,
    'downloads' => downloads,
    'applications' => applications,
    'volume' => volume,
    'server' => server,
    'archive' => archive,
    'close' => close,
    'help' => help,
    'play' => play,
    'pause' => pause,
    'soundOn' => soundOn,
    'soundOff' => soundOff,
    'enterFullScreen' => enterFullScreen,
    'exitFullScreen' => exitFullScreen,
    _ => null,
  };
}

/// Глиф строкой — для мест, где иконка идёт внутри текста, а не отдельным
/// виджетом: например, стрелка в описании ссылки.
extension FcIconGlyph on FcIcons {
  String glyph(IconData icon) => String.fromCharCode(icon.codePoint);
}
