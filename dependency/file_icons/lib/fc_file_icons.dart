/// Иконка строки по правилам.
///
/// Спецификация — `docs/spec/file-icons.md`. Наружу торчит модуль; сама служба
/// объявлена в `fc_ui_api`, а значок системы приносит платформенный модуль
/// приложения — без него правила с `system` просто не совпадают.
library;

export 'src/file_icon_service.dart' show FileIconService;
export 'src/file_icon_settings.dart';
export 'src/file_icons_module.dart';
export 'src/picture_files.dart' show PictureFiles;
