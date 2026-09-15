import 'dart:collection';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

/// Ширина строки, набранной этим стилем.
///
/// Считается с памятью: один и тот же вопрос задаётся десятками раз за кадр.
/// Строка таблицы спрашивает о каждой ячейке, краткий вид — обо всех именах
/// каталога сразу, и каждый ответ — это набор строки в `TextPainter`. Полсотни
/// строк на восемь колонок — четыреста наборов за кадр, а обещано шестьдесят
/// кадров в секунду на каталоге в сто тысяч записей (`docs/widgets.md`, §4).
double textWidthOf(String text, TextStyle style, TextScaler scaler) {
  final key = (text, style, scaler);
  final remembered = _widths[key];
  if (remembered != null) {
    return remembered;
  }

  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();

  // Помнится последнее, а старое забывается: имена уходят с экрана и больше не
  // спрашиваются, а расти без предела память не вправе.
  if (_widths.length >= _widthsLimit) {
    _widths.remove(_widths.keys.first);
  }
  _widths[key] = width;

  return width;
}

/// Ширина по вопросу целиком: стиль и масштаб — часть вопроса, а не догадка.
/// Сменилась тема или крупность текста — ответы прежние не подойдут, и ключ
/// сам это учитывает.
final LinkedHashMap<(String, TextStyle, TextScaler), double> _widths = LinkedHashMap();

const int _widthsLimit = 1024;

/// Ширина набранного куска: текст в нём может быть разных стилей.
///
/// Отдельно от [textWidthOf]: строка состояния набирает имя ссылки, стрелку
/// глифом шрифта значков и цель — тремя стилями, и сложить их ширины по
/// отдельности значило бы забыть про кернинг на стыках. Памяти здесь нет:
/// таких мест единицы, и спрашивают они раз на перерисовку, а не на строку.
double spanWidthOf(InlineSpan span, TextScaler scaler) {
  final painter = TextPainter(text: span, textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Поместится ли строка в отведённое.
///
/// Вопрос задаётся там, где текст режется: обрезанному нужна подсказка,
/// поместившемуся — нет (`docs/spec/tooltips.md`, §2). `TextOverflow.ellipsis`
/// на этот вопрос не отвечает: он молча рисует многоточие, — поэтому меряем
/// сами, и меряем **тем же**, чем рисуем.
///
/// Вставшая впритык строка считается поместившейся: иначе на каждой ровно
/// уложившейся строке висела бы подсказка, повторяющая видимое.
bool textFits(String text, TextStyle style, double maxWidth, TextScaler scaler) {
  if (text.isEmpty || maxWidth.isInfinite) {
    return true;
  }
  if (maxWidth <= 0) {
    // Места не отведено вовсе — рисовать нечего, и договаривать нечего.
    return true;
  }
  return textWidthOf(text, style, scaler) <= maxWidth;
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
