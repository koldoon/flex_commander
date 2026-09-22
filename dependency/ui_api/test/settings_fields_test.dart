import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поля оформления: дробное число и цвет (`docs/spec/theme-editor.md`, §4).
void main() {
  group('дробное число', () {
    SettingsDecimal fieldWith(double value, {double min = 0, double max = 400}) {
      var stored = value;
      return SettingsField.decimal(
        'rowHeight',
        title: 'Row height',
        min: min,
        max: max,
        defaultValue: 22,
        read: () => stored,
        write: (next) => stored = next,
      );
    }

    test('доли разбираются — ради них вид и заведён', () {
      expect(fieldWith(1, min: 0.05, max: 1).parse('0.75'), 0.75);
    });

    test('запятая считается точкой: на русской раскладке дробное набирают ею', () {
      expect(fieldWith(1).parse('1,5'), 1.5);
    });

    test('набранное за пределами прижимается к ним, не-число — ничто', () {
      final field = fieldWith(22);

      expect(field.parse('1000'), 400);
      expect(field.parse('-5'), 0);
      expect(field.parse('сто'), isNull);
      // Бесконечность — тоже не число: `double.tryParse` её разбирает, а
      // раскладка от неё падает.
      expect(field.parse('Infinity'), isNull);
    });

    test('набором приезжает и круглое: в json `22.0` читается как `22`', () {
      final field = fieldWith(30)..apply(22);

      expect(field.read(), 22.0);
      expect(field.isDefault, isTrue);
    });
  });

  group('цвет', () {
    test('решётка необязательна, регистр любой, шесть знаков — непрозрачный', () {
      expect(parseColor('#FF2D6CDF'), const Color(0xFF2D6CDF));
      expect(parseColor('2d6cdf'), const Color(0xFF2D6CDF));
      expect(parseColor(' #00000000 '), const Color(0x00000000));
    });

    test('недописанное и чужое — ничто, а не чёрный', () {
      expect(parseColor('#FF2'), isNull);
      expect(parseColor(''), isNull);
      expect(parseColor('#ZZZZZZ'), isNull);
    });

    test('записывается всегда с альфой: прозрачный от чёрного отличим', () {
      expect(formatColor(const Color(0x00000000)), '#00000000');
      expect(formatColor(const Color(0xFF000000)), '#FF000000');
    });

    test('в настройках цвет лежит строкой и читается обратно', () {
      var stored = const Color(0xFF2D6CDF);
      final field = SettingsField.color(
        'cursorBackground',
        title: 'Cursor background',
        defaultValue: const Color(0xFF2D6CDF),
        read: () => stored,
        write: (next) => stored = next,
      );

      expect(field.value, '#FF2D6CDF');

      field.apply('#80FFFFFF');
      expect(stored, const Color(0x80FFFFFF));
      expect(field.isDefault, isFalse);

      // Испорченное — молча мимо: правка могла приехать из другого выпуска
      // (сквозное правило 5).
      field.apply('не цвет');
      expect(stored, const Color(0x80FFFFFF));

      field.resetToDefault();
      expect(field.isDefault, isTrue);
    });
  });
}
