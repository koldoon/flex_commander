import 'package:flutter/painting.dart';

/// Разбор текста на цветные куски — по строкам.
///
/// Интерфейс, а не прямое обращение к библиотеке: подсветка — самая
/// заменяемая часть просмотрщика (языки, качество разбора, сама библиотека),
/// а всё остальное от неё зависеть не должно. Показ просит строку и получает
/// [TextSpan] — знает ли кто-то в этом файле про синтаксис, ему всё равно.
abstract interface class SyntaxHighlighter {
  /// Разбирает **весь** текст сразу и отдаёт по спану на строку.
  ///
  /// Весь, а не построчно: многострочный комментарий или строковый литерал
  /// иначе не разобрать — начало у них в одной строке, конец в другой.
  ///
  /// [fileName] — по нему выбирается язык: ничего другого о файле подсветке
  /// знать не нужно.
  List<TextSpan> highlight(List<String> lines, {required String fileName, required TextStyle base});
}

/// Без подсветки: строка как есть.
///
/// Не заглушка на время, а рабочий случай: расширение может быть незнакомым,
/// а подсветку — отключить.
class PlainHighlighter implements SyntaxHighlighter {
  const PlainHighlighter();

  @override
  List<TextSpan> highlight(List<String> lines, {required String fileName, required TextStyle base}) => [
    for (final line in lines) TextSpan(text: line, style: base),
  ];
}
