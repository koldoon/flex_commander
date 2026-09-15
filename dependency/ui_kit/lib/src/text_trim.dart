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

/// Обрезает путь **слева**, по целым звеньям: `/…/Qwickserve/dist`.
///
/// Конец строки важнее — в нём текущий каталог; но и начало не пустое место: по
/// нему видно, о каком корне речь, — свой диск это или `ssh://koldoon@shark`
/// (`docs/spec/panel-crumbs.md`, §2). Тем же корнем начинаются звенья пути, и
/// правило у них одно — `pathRootOf`.
///
/// **По звеньям, а не по буквам.** Обрубок посреди имени (`/…eveloper/Petrosoft`)
/// читается как другое имя: глаз сперва принимает его за настоящее и только
/// потом замечает многоточие. Целые звенья читаются сразу, и цена этому —
/// несколько точек пустоты справа.
///
/// Не влезает и одно звено — режем его буквами: показать хвост важнее, чем
/// соблюсти правило.
///
/// Правило одно на всё приложение: плашка пути, список пройденного и список
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

  final root = pathRootOf(value);
  final parts = value.substring(root.length).split('/').where((part) => part.isNotEmpty).toList();
  // Начало показанного: корень и многоточие вместо отброшенных звеньев.
  final head = root.endsWith('/') ? '$root…' : '$root/…';

  // Отбрасываем звенья с головы, пока остаток не поместится.
  for (var skip = 1; skip < parts.length; skip++) {
    final shown = '$head/${parts.skip(skip).join('/')}';
    if (textWidthOf(shown, style, scaler) <= maxWidth) {
      return shown;
    }
  }

  return _trimByLetters(value, style, maxWidth, scaler);
}

/// Обрезка буквами: для строк без звеньев и для звена, которое само не влезло.
String _trimByLetters(String value, TextStyle style, double maxWidth, TextScaler scaler) {
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
