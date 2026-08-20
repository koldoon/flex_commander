import 'dart:convert';

import 'package:fc_viewer/fc_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подготовка текста к показу: файлы приходят с разных машин и в разном виде.
void main() {
  group('переводы строк приводятся к одному виду', () {
    test('unix — как есть', () {
      expect(TextDocument.parse('раз\nдва\nтри').text, 'раз\nдва\nтри');
    });

    test('windows', () {
      expect(TextDocument.parse('раз\r\nдва').text, 'раз\nдва');
    });

    test('старый mac — одиночный возврат каретки', () {
      expect(TextDocument.parse('раз\rдва').text, 'раз\nдва');
    });

    test('вперемешку', () {
      expect(TextDocument.parse('раз\r\nдва\nтри\rчетыре').text, 'раз\nдва\nтри\nчетыре');
    });

    test('одиночных возвратов каретки не остаётся', () {
      // Показ знает только про `\n`: не приведённый `\r` встал бы в тексте
      // видимым мусором.
      expect(TextDocument.parse('раз\r\n\rдва').text, isNot(contains('\r')));
    });
  });

  group('края', () {
    test('пустой файл — пустой текст, а не ошибка', () {
      expect(TextDocument.parse('').text, isEmpty);
    });

    test('завершающий перевод строки сохраняется', () {
      // Он есть в файле, значит есть и на экране: последняя строка пустая.
      expect(TextDocument.parse('раз\nдва\n').text, 'раз\nдва\n');
    });

    test('пустые строки внутри сохраняются', () {
      expect(TextDocument.parse('раз\n\nтри').text, 'раз\n\nтри');
    });
  });

  test('битые байты не роняют разбор', () {
    // Файл может оказаться и не текстом вовсе: показать знаки замены честнее,
    // чем отказаться открывать. Этим просмотрщик и отличается от редактора —
    // тот читает строго, потому что ещё и пишет.
    final text = utf8.decode([0xC3, 0x28, 0x41], allowMalformed: true);

    expect(TextDocument.parse(text).text, text);
  });
}
