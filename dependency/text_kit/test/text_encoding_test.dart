import 'dart:convert';

import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Кодировки (`docs/spec/text-encodings.md`, §2–3).
void main() {
  const russian =
      'Мороз и солнце; день чудесный! Ещё ты дремлешь, друг прелестный - '
      'пора, красавица, проснись: открой сомкнуты негой взоры навстречу '
      'северной Авроры, звездою севера явись!';
  const ukrainian =
      'Садок вишневий коло хати, хрущі над вишнями гудуть, '
      'плугатарі з плугами йдуть, співають ідучи дівчата.';

  group('таблицы', () {
    test('«Привет» в известных байтах', () {
      const known = {
        TextEncoding.windows1251: [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2],
        TextEncoding.koi8r: [0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4],
        TextEncoding.cp866: [0x8F, 0xE0, 0xA8, 0xA2, 0xA5, 0xE2],
      };
      for (final MapEntry(key: encoding, value: bytes) in known.entries) {
        expect(encoding.decode(bytes), 'Привет', reason: encoding.label);
        expect(encoding.encode('Привет'), bytes, reason: encoding.label);
      }
    });

    test('каждый определённый байт идёт по кругу', () {
      for (final encoding in TextEncoding.values.where((encoding) => !encoding.isUnicode)) {
        for (var byte = 0; byte < 256; byte++) {
          final String text;
          try {
            text = encoding.decode([byte], strict: true);
          } on FormatException {
            continue;
          }
          expect(encoding.encode(text), [byte], reason: '${encoding.label} 0x${byte.toRadixString(16)}');
        }
      }
    });

    test('дыра в таблице: строго — отказ, мягко — знак замены', () {
      expect(() => TextEncoding.windows1251.decode([0x98], strict: true), throwsFormatException);
      expect(TextEncoding.windows1251.decode([0x98]), '�');
    });

    test('что не помещается — названо местом', () {
      expect(TextEncoding.koi8r.unencodable('цена 5 €'), 7);
      expect(TextEncoding.windows1251.unencodable('цена 5 €'), isNull);
      expect(TextEncoding.utf8.unencodable('€'), isNull);
      expect(() => TextEncoding.koi8r.encode('€'), throwsFormatException);
    });

    test('UTF-16 в обе стороны', () {
      for (final encoding in [TextEncoding.utf16le, TextEncoding.utf16be]) {
        expect(encoding.decode(encoding.encode('Привет, 😀')), 'Привет, 😀');
      }
    });
  });

  group('определение', () {
    test('русский текст узнаётся в каждой кириллической кодировке', () {
      for (final encoding in [
        TextEncoding.windows1251,
        TextEncoding.koi8r,
        TextEncoding.cp866,
        TextEncoding.macCyrillic,
        TextEncoding.iso88595,
      ]) {
        expect(TextEncoding.detect(encoding.encode(russian)), encoding, reason: encoding.label);
      }
    });

    test('украинский в KOI8-U — не KOI8-R', () {
      expect(TextEncoding.detect(TextEncoding.koi8u.encode(ukrainian)), TextEncoding.koi8u);
    });

    test('короткая строка тоже: «Привет, мир»', () {
      for (final encoding in [TextEncoding.windows1251, TextEncoding.koi8r, TextEncoding.cp866]) {
        expect(TextEncoding.detect(encoding.encode('Привет, мир')), encoding, reason: encoding.label);
      }
    });

    test('UTF-8, ASCII и метки', () {
      expect(TextEncoding.detect(utf8.encode(russian)), TextEncoding.utf8);
      expect(TextEncoding.detect(ascii.encode('plain text')), TextEncoding.utf8);
      expect(TextEncoding.detect([0xEF, 0xBB, 0xBF, ...utf8.encode('x')]), TextEncoding.utf8);
      expect(TextEncoding.detect([0xFF, 0xFE, ...TextEncoding.utf16le.encode('x')]), TextEncoding.utf16le);
      expect(TextEncoding.detect([0xFE, 0xFF, ...TextEncoding.utf16be.encode('x')]), TextEncoding.utf16be);
    });

    test('французский в Windows-1252 — не кириллица', () {
      final bytes = TextEncoding.windows1252.encode('Le café est très bon, à côté de la forêt.');
      expect(TextEncoding.detect(bytes), TextEncoding.windows1252);
    });

    test('UTF-8, обрезанный посреди знака, — всё ещё UTF-8', () {
      final long = utf8.encode('я' * (TextEncoding.sampleSize ~/ 2 + 1));
      expect(TextEncoding.detect(long), TextEncoding.utf8);
    });
  });

  group('EncodedText', () {
    test('метка снимается при чтении и возвращается при записи', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('текст')];
      final read = EncodedText.read(bytes)!;
      expect(read.text, 'текст');
      expect(read.bom, isTrue);
      expect(read.bytes, bytes);
    });

    test('строгое чтение не берёт того, что испортится при записи', () {
      expect(EncodedText.read([0x98, 0x00, 0xFF], as: TextEncoding.windows1251, strict: true), isNull);
    });
  });
}
