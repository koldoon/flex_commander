import 'package:flutter/painting.dart';

/// Цвет строкой: `#AARRGGBB`.
///
/// Здесь, у оформления, а не у настроек: цвет так пишут и в теме, и в файле
/// настроек, и в поле ввода редактора тем — разбор у всех троих обязан быть
/// один (`docs/spec/theme-editor.md`, §4).

/// Разбирает `#RRGGBB` и `#AARRGGBB`; решётка необязательна, регистр любой.
///
/// Без альфы — непрозрачный: шесть знаков пишут именно тогда, когда о
/// прозрачности не думают. Не разобралось — null: подставлять чёрный вместо
/// набранного значило бы соврать про цвет.
Color? parseColor(String text) {
  final digits = text.trim().replaceFirst('#', '');
  if (digits.length != 6 && digits.length != 8) {
    return null;
  }
  final parsed = int.tryParse(digits, radix: 16);
  if (parsed == null) {
    return null;
  }
  return Color(digits.length == 6 ? 0xFF000000 | parsed : parsed);
}

/// Всегда с альфой: `#00000000` и `#FF000000` — разные цвета, и укороченная
/// запись их путала бы.
String formatColor(Color color) => '#${color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}';
