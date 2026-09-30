import 'dart:convert';

import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Место сбоя разбора: смещение в знаках — в строку и столбец.
void main() {
  group('место сбоя', () {
    test('смещение переводится в строку и столбец', () {
      const text = '{\n  "a": 1,\n  "b": ,\n}';
      try {
        jsonDecode(text);
        fail('ожидался отказ');
      } on FormatException catch (error) {
        final place = placeOfError(error, text);

        expect(place, isNotNull);
        expect(place!.line, 3, reason: 'сломалось на третьей строке');
        expect(place.column, greaterThan(1));
      }
    });

    test('столбец считается от начала строки, а не от начала текста', () {
      // Проверка именно того, что перевод не врёт: смещение 14 в четвёртой
      // строке — это столбец 3, а не 15.
      const text = 'aa\nbb\ncc\ndd\n1234';
      const error = FormatException('сломалось', text, 14);
      final place = placeOfError(error, text);

      expect(place!.line, 5);
      expect(place.column, 3);
    });

    test('смещения нет — места тоже нет, и это не падение', () {
      expect(placeOfError(const FormatException('без места'), '{}'), isNull);
    });

    test('смещение за концом текста не выводит за край', () {
      const text = 'один\nдва';
      final place = placeOfError(const FormatException('сломалось', text, 1000), text);

      expect(place!.line, 2, reason: 'дальше последней строки уехать некуда');
    });
  });
}
