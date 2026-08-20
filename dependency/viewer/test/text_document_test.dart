import 'dart:convert';

import 'package:fc_viewer/fc_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор текста на строки: файлы приходят с разных машин и в разном виде.
void main() {
  group('переводы строк', () {
    test('unix', () {
      final document = TextDocument.parse('раз\nдва\nтри');

      expect(document.lines, ['раз', 'два', 'три']);
      expect(document.lineCount, 3);
    });

    test('windows', () {
      expect(TextDocument.parse('раз\r\nдва').lines, ['раз', 'два']);
    });

    test('старый mac — одиночный возврат каретки', () {
      expect(TextDocument.parse('раз\rдва').lines, ['раз', 'два']);
    });

    test('вперемешку', () {
      expect(TextDocument.parse('раз\r\nдва\nтри\rчетыре').lines, ['раз', 'два', 'три', 'четыре']);
    });
  });

  group('края', () {
    test('завершающий перевод лишней строки не создаёт', () {
      // В файле, оканчивающемся переводом, строк столько же, сколько их видит
      // редактор.
      expect(TextDocument.parse('раз\nдва\n').lines, ['раз', 'два']);
    });

    test('два перевода подряд в конце — это пустая строка', () {
      expect(TextDocument.parse('раз\n\n').lines, ['раз', '']);
    });

    test('пустой файл — одна пустая строка, а не ноль', () {
      // Показывать пустоту всё равно чем-то надо, и «ноль строк» сломало бы
      // счёт в списке.
      expect(TextDocument.parse('').lines, ['']);
      expect(TextDocument.empty().lines, ['']);
    });

    test('файл из одного перевода строки', () {
      expect(TextDocument.parse('\n').lines, ['']);
    });

    test('пустые строки внутри сохраняются', () {
      expect(TextDocument.parse('раз\n\nтри').lines, ['раз', '', 'три']);
    });
  });

  group('самая длинная строка', () {
    test('считается в символах, а не в байтах', () {
      // Ширина холста меряется знаками моноширинного шрифта: кириллица в
      // utf-8 занимает два байта, а места — одно знакоместо.
      final document = TextDocument.parse('аб\nабвгд\nв');

      expect(document.longestLine, 5);
      expect(utf8.encode('абвгд').length, 10);
    });

    test('у пустого документа — ноль', () {
      expect(TextDocument.parse('').longestLine, 0);
    });
  });

  group('чтение', () {
    test('битые байты не роняют разбор', () {
      // Файл может оказаться и не текстом вовсе: показать знаки замены
      // честнее, чем отказаться открывать.
      final text = utf8.decode([0xC3, 0x28, 0x41], allowMalformed: true);

      expect(TextDocument.parse(text).lines, hasLength(1));
    });
  });
}
