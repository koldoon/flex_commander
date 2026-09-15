import 'package:fc_api/fc_api.dart';
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

/// Обрезает путь **слева**, оставляя корень: `/…/Qwickserve/dist`.
///
/// Конец строки важнее — в нём текущий каталог; но и начало не пустое место:
/// по нему видно, о каком корне речь, — свой диск это или `ssh://koldoon@shark`
/// (`docs/spec/panel-crumbs.md`, §2). Тем же корнем начинаются звенья пути, и
/// правило у них одно — `pathRootOf`.
///
/// Правило одно и на всё приложение: плашка пути, список пройденного и список
/// наборов режут одинаково, иначе один и тот же путь выглядел бы в трёх местах
/// по-разному (`docs/spec/session-history.md`, §9).
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

  // Корень показывается, пока сам помещается вместе с многоточием и хотя бы
  // одной буквой хвоста; не помещается — режем как раньше, без него.
  final root = pathRootOf(value);
  final head = root.isEmpty || textWidthOf('$root…', style, scaler) >= maxWidth ? '…' : '$root…';

  // Двоичный поиск самого длинного хвоста, который помещается вместе с началом.
  var low = root.length;
  var high = value.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (textWidthOf('$head${value.substring(middle)}', style, scaler) <= maxWidth) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return '$head${value.substring(low)}';
}
