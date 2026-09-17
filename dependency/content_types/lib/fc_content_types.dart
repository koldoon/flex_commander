/// Тип файла по его содержимому.
///
/// Спецификация — `docs/spec/content-types.md`. Наружу отсюда торчит только
/// модуль: сама служба объявлена в `fc_ui_api`, а таблица сигнатур — забота
/// этого пакета и никого больше.
library;

export 'src/content_type_table.dart' show ContentSignature, ContentTypeTable;
export 'src/content_types_module.dart';
export 'src/content_types_settings.dart';
export 'src/content_type_service.dart' show ContentTypeService;
// Правило «текст или двоичное» нужно и поиску: он отсеивает двоичные файлы
// по началу, и второй ответ на тот же вопрос разошёлся бы с этим молча
// (`docs/spec/file-search.md`, §11.2).
export 'src/text_probe.dart' show textOrBinary;
