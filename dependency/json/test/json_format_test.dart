import 'package:fc_json/fc_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// Форматтер json: текст на входе, текст на выходе.
///
/// Чистый Dart: ни Flutter, ни файлов — проверяется обычными тестами.
void main() {
  group('вид', () {
    test('объект разворачивается по строкам с отступом в два пробела', () {
      expect(formatJson('{"a":1,"b":2}'), '{\n  "a": 1,\n  "b": 2\n}\n');
    });

    test('массив тоже', () {
      expect(formatJson('[1,2]'), '[\n  1,\n  2\n]\n');
    });

    test('вложенность отступается вглубь', () {
      expect(formatJson('{"a":{"b":[1]}}'), '{\n  "a": {\n    "b": [\n      1\n    ]\n  }\n}\n');
    });

    test('пустые остаются пустыми, а не разворачиваются', () {
      expect(formatJson('{}'), '{}\n');
      expect(formatJson('[]'), '[]\n');
    });

    test('в конце файла один перевод строки', () {
      // Ни ноль, ни два: файл кладут в систему контроля версий.
      expect(formatJson('{"a":1}').endsWith('}\n'), isTrue);
      expect(formatJson('{"a":1}').endsWith('}\n\n'), isFalse);
    });

    test('верхний уровень бывает и не объектом', () {
      expect(formatJson('42'), '42\n');
      expect(formatJson('"текст"'), '"текст"\n');
      expect(formatJson('null'), 'null\n');
    });
  });

  group('содержимое не меняется', () {
    test('порядок ключей сохраняется, а не сортируется', () {
      // Отформатированный файл кладут обратно в систему контроля версий, и
      // разница должна остаться читаемой.
      expect(formatJson('{"b":1,"a":2,"c":3}'), '{\n  "b": 1,\n  "a": 2,\n  "c": 3\n}\n');
    });

    test('кириллица остаётся кириллицей, а не уезжает в \\u', () {
      expect(formatJson('{"имя":"значение"}'), contains('"имя": "значение"'));
    });

    test('уже отформатированное не меняется во второй раз', () {
      final once = formatJson('{"a":[1,{"b":2}]}');

      expect(formatJson(once), once);
    });

    test('ключ с кавычками и переводом строки экранируется обратно', () {
      expect(formatJson(r'{"a":"раз\nдва"}'), contains(r'"раз\nдва"'));
    });
  });

  group('число теряет запись, и это сказано вслух', () {
    test('разбор уже потерял, как оно было написано', () {
      // `dart:convert` отдаёт число, а не его запись: `1e3` возвращается как
      // `1000.0`. Обещать сохранность записи, которой нет, было бы обманом
      // (`docs/spec/formatters.md`, §7).
      expect(formatJson('{"a":1e3}'), '{\n  "a": 1000.0\n}\n');
      expect(formatJson('{"a":1.0}'), '{\n  "a": 1.0\n}\n');
      expect(formatJson('{"a":1}'), '{\n  "a": 1\n}\n');
    });
  });

  group('кривое не форматируется', () {
    test('обрыв бросает отказ с местом', () {
      expect(() => formatJson('{"a":'), throwsFormatException);
    });

    test('пустой текст — тоже отказ', () {
      expect(() => formatJson(''), throwsFormatException);
    });

    test('хвост после значения не проглатывается', () {
      expect(() => formatJson('{} лишнее'), throwsFormatException);
    });
  });
}
