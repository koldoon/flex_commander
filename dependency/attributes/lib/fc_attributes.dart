/// Правка атрибутов объекта: права, даты, владелец, расширенные атрибуты.
///
/// Модуль обеих половин: окно и команда — на экране, работа `attrs.apply` — в
/// ядре, там же, где живут источники. Выключен — пропадают команда, клавиша,
/// работа и кнопка в окне сведений; примитивы провайдеров остаются и никому не
/// мешают.
///
/// Спецификация — `docs/spec/file-attributes.md`.
library;

export 'src/attribute_edits.dart';
export 'src/attributes_command.dart';
export 'src/attributes_module.dart';
export 'src/attributes_run.dart';
export 'src/xattr_info_provider.dart';
