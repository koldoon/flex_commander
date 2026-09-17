import 'dart:convert';

import 'package:fc_search/fc_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сличение содержимого: байтовые образцы и чтение кусками
/// (`docs/spec/file-search.md`, §11.4).
void main() {
  /// Скормить текст сканеру **по кускам** заданной длины — так и приходят
  /// байты от источника.
  bool scan(ContentRule rule, List<int> bytes, {int piece = 10}) {
    final run = ContentScan(rule);
    for (var at = 0; at < bytes.length; at += piece) {
      run.feed(bytes.sublist(at, (at + piece).clamp(0, bytes.length)));
    }
    return run.close() || run.found;
  }

  bool find(
    String needle,
    String haystack, {
    int piece = 10,
    bool regexp = false,
    bool caseSensitive = false,
    bool wholeWords = false,
    bool allCharsets = false,
  }) => scan(
    ContentRule.parse(
      needle,
      regexp: regexp,
      caseSensitive: caseSensitive,
      wholeWords: wholeWords,
      allCharsets: allCharsets,
    ),
    utf8.encode(haystack),
    piece: piece,
  );

  group('байтовый поиск', () {
    test('находит и не находит', () {
      expect(find('todo', 'here is a todo item'), isTrue);
      expect(find('todo', 'nothing here'), isFalse);
    });

    test('совпадение на стыке кусков', () {
      // Главная ошибка этапа: без хвоста разорванное границей чтения пропадает
      // молча. Куски по два байта — образец разрезан наверняка.
      expect(find('needle', 'a haystack with a needle inside', piece: 2), isTrue);
      expect(find('needle', 'a haystack with a needle inside', piece: 3), isTrue);
      expect(find('needle', 'a haystack with a needle inside', piece: 1), isTrue);
    });

    test('хвост не рождает совпадений из ничего', () {
      expect(
        find(
          'abcd',
          'ab'
              'xy'
              'cd',
          piece: 2,
        ),
        isFalse,
        reason: 'склеилось бы из двух кусков',
      );
    });

    test('регистр — по просьбе', () {
      expect(find('TODO', 'a todo item'), isTrue, reason: 'по умолчанию всё равно');
      expect(find('TODO', 'a todo item', caseSensitive: true), isFalse);
      expect(find('todo', 'a TODO item'), isTrue);
    });

    test('слово целиком', () {
      expect(find('do', 'done deal', wholeWords: true), isFalse);
      expect(find('do', 'do it', wholeWords: true), isTrue);
      expect(find('do', 'just (do) this', wholeWords: true), isTrue);
      expect(find('do', 'todo', wholeWords: true), isFalse);
    });

    test('кириллица в UTF-8 — и регистр тоже', () {
      expect(find('файл', 'открытый файл здесь'), isTrue);
      expect(find('ФАЙЛ', 'открытый файл здесь'), isTrue);
      expect(find('ФАЙЛ', 'открытый файл здесь', caseSensitive: true), isFalse);
      expect(find('файл', 'открытый ФаЙл здесь'), isTrue, reason: 'смешанный регистр тоже');
    });
  });

  group('любые кодировки', () {
    /// Те же слова, записанные однобайтовыми кодировками.
    List<int> cp1251(String text) => [
      for (final code in text.runes)
        if (code < 0x80)
          code
        else if (code >= 0x410 && code <= 0x42f)
          0xc0 + (code - 0x410)
        else if (code >= 0x430 && code <= 0x44f)
          0xe0 + (code - 0x430)
        else
          0x3f,
    ];

    test('кириллица находится в CP1251, когда попросили', () {
      final bytes = cp1251('открытый файл здесь');

      expect(scan(ContentRule.parse('файл'), bytes), isFalse, reason: 'UTF-8 таких байт не знает');
      expect(scan(ContentRule.parse('файл', allCharsets: true), bytes), isTrue);
    });

    test('регистр работает и в однобайтовой кодировке', () {
      final bytes = cp1251('открытый ФАЙЛ здесь');

      expect(scan(ContentRule.parse('файл', allCharsets: true), bytes), isTrue);
      expect(scan(ContentRule.parse('файл', allCharsets: true, caseSensitive: true), bytes), isFalse);
    });

    test('латиница даёт один образец на все кодировки', () {
      // Проверяется через поведение: лишние образцы искали бы то же самое.
      expect(find('todo', 'a todo item', allCharsets: true), isTrue);
    });
  });

  group('выражение', () {
    test('ищется по тексту', () {
      expect(find(r'\d+', 'файл версии 42', regexp: true), isTrue);
      expect(find(r'\d+', 'файл без чисел', regexp: true), isFalse);
    });

    test('через границу кусков — тоже', () {
      expect(find(r'ver\d+', 'in the middle ver42 of a line', regexp: true, piece: 2), isTrue);
    });

    test('последняя строка без перевода не пропадает', () {
      expect(find('конец', 'первая строка\nконец без перевода', regexp: true, piece: 3), isTrue);
    });

    test('неверное выражение ничего не находит и не бросает', () {
      final rule = ContentRule.parse('*.dart', regexp: true);

      expect(rule.isValid, isFalse);
      expect(scan(rule, utf8.encode('*.dart')), isFalse);
    });

    test('слово целиком действует и в выражении', () {
      expect(find('do', 'done', regexp: true, wholeWords: true), isFalse);
      expect(find('do', 'do it', regexp: true, wholeWords: true), isTrue);
    });
  });

  test('пустое правило не ищет ничего', () {
    final rule = ContentRule.parse('');

    expect(rule.isEmpty, isTrue);
    expect(rule.isValid, isTrue);
    expect(scan(rule, utf8.encode('что угодно')), isFalse);
  });
}
