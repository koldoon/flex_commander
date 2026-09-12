import 'package:flutter/widgets.dart';

/// Ширина строки, набранной этим стилем.
double textWidthOf(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Обрезает путь **слева**: конец строки важнее — в нём текущий каталог.
///
/// Правило одно на всё приложение: и плашка пути, и список пройденного режут
/// одинаково, иначе один и тот же путь выглядел бы в двух местах по-разному
/// (`docs/spec/session-history.md`, §9).
///
/// Считается вручную, а не через `TextOverflow.ellipsis`: тот всегда режет
/// хвост, а разворот направления текста ломает порядок символов в пути.
String trimTextHead(String value, TextStyle style, double maxWidth, TextScaler scaler) {
  if (maxWidth.isInfinite || maxWidth <= 0) {
    return value;
  }

  if (textWidthOf(value, style, scaler) <= maxWidth) {
    return value;
  }

  // Двоичный поиск самого длинного хвоста, который помещается вместе с «…».
  var low = 0;
  var high = value.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (textWidthOf('…${value.substring(middle)}', style, scaler) <= maxWidth) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return '…${value.substring(low)}';
}
