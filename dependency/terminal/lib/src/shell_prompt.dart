import 'package:xterm/xterm.dart';

/// Кусок приглашения, набранный одним цветом и начертанием.
class ShellPromptRun {
  const ShellPromptRun({required this.text, required this.color, this.bold = false, this.italic = false});

  final String text;

  /// Цвет **как его хранит терминал** — числом, а не готовым `Color`.
  ///
  /// Разбирать его в цвет здесь нечем и незачем: для этого нужна палитра, а она
  /// живёт в теме, то есть в дереве виджетов ([TerminalPalette]). Сюда цвет
  /// приезжает таким, каким его записал терминал, и тем же числом отдаётся тому,
  /// кто рисует.
  final int color;

  final bool bold;
  final bool italic;

  @override
  String toString() => 'ShellPromptRun($text, $color${bold ? ', bold' : ''}${italic ? ', italic' : ''})';
}

/// Приглашение, снятое с экрана терминала.
///
/// Снимается готовым, а не просится у оболочки: она его уже собрала и уже
/// напечатала (`docs/spec/shell-prompt.md`, §3).
class ShellPrompt {
  const ShellPrompt(this.lines);

  static const ShellPrompt none = ShellPrompt([]);

  /// Логические строки — переносы по краю экрана уже сшиты.
  final List<List<ShellPromptRun>> lines;

  bool get isEmpty => lines.every((line) => line.every((run) => run.text.trim().isEmpty));

  /// Что показывается в строке команд: последняя строка приглашения.
  ///
  /// Строка у нас одна, а приглашение бывает многострочным (`starship` по
  /// умолчанию двухстрочный). Последняя — та, за которой сразу идёт ввод.
  List<ShellPromptRun> get lastLine => lines.isEmpty ? const [] : lines.last;

  /// Всё целиком — то, что договаривает подсказка.
  String get text => [for (final line in lines) line.map((run) => run.text).join()].join('\n');

  /// Текст последней строки — по нему меряют и режут.
  String get lastText => lastLine.map((run) => run.text).join();
}

/// Снимает приглашение из буфера терминала: от того места, где оболочка
/// отметилась, до того, где остановился курсор.
///
/// Метка приходит из `precmd` — **до** печати приглашения, поэтому её место и
/// есть начало. Конец — курсор после того, как печать утихла: пока человек
/// набирает в нашей строке, оболочка не печатает ничего, ввод в PTY не уходит
/// до `Enter`.
///
/// Чистой функцией над буфером, а не методом сессии: так её проверяет
/// **настоящий** терминал, которому написали настоящие последовательности, —
/// подставка тут подтвердила бы любую ошибку разбора.
ShellPrompt readShellPrompt(
  Buffer buffer, {
  required int startLine,
  required int startColumn,
  required int endLine,
  required int endColumn,
}) {
  if (endLine < startLine || (endLine == startLine && endColumn <= startColumn)) {
    return ShellPrompt.none;
  }

  final lines = <List<ShellPromptRun>>[];
  var current = <ShellPromptRun>[];

  for (var at = startLine; at <= endLine && at < buffer.lines.length; at++) {
    final line = buffer.lines[at];

    // Перенос по краю экрана — не новая строка приглашения, а продолжение той
    // же: терминал шириной 80 колонок, пока его никто не показал, и длинное
    // приглашение переносится (`docs/spec/shell-prompt.md`, §4).
    if (at > startLine && !line.isWrapped) {
      lines.add(current);
      current = <ShellPromptRun>[];
    }

    final from = at == startLine ? startColumn : 0;
    final to = at == endLine ? endColumn : line.length;
    current.addAll(_runsOf(line, from, to));
  }

  lines.add(current);
  return ShellPrompt([for (final line in lines) _tidy(line)]);
}

/// Ячейки строки — кусками одного цвета и начертания.
List<ShellPromptRun> _runsOf(BufferLine line, int from, int to) {
  final runs = <ShellPromptRun>[];
  final text = StringBuffer();
  var color = 0;
  var bold = false;
  var italic = false;
  var started = false;

  void flush() {
    if (text.isNotEmpty) {
      runs.add(ShellPromptRun(text: text.toString(), color: color, bold: bold, italic: italic));
      text.clear();
    }
  }

  for (var at = from; at < to && at < line.length; at++) {
    final code = line.getCodePoint(at);
    final flags = line.getAttributes(at);
    // Невидимое и мигающее не переносим: в строке интерфейса мигание — шум, а
    // невидимый текст был бы враньём. Подчёркивание опускаем по той же причине,
    // по какой опускаем фон: строка команд не терминал.
    final cellColor = line.getForeground(at);
    final cellBold = flags & CellFlags.bold != 0;
    final cellItalic = flags & CellFlags.italic != 0;

    if (!started || cellColor != color || cellBold != bold || cellItalic != italic) {
      flush();
      color = cellColor;
      bold = cellBold;
      italic = cellItalic;
      started = true;
    }

    // Пустая ячейка — пробел: терминал хранит непечатанное нулём.
    text.writeCharCode(code == 0 ? 0x20 : code);
  }

  flush();
  return runs;
}

/// Убирает хвостовые пробелы: строка кончается там, где кончился текст.
List<ShellPromptRun> _tidy(List<ShellPromptRun> runs) {
  final tidy = [...runs];
  while (tidy.isNotEmpty) {
    final last = tidy.last;
    final text = last.text.replaceFirst(RegExp(r'\s+$'), '');
    if (text.isNotEmpty) {
      tidy[tidy.length - 1] = ShellPromptRun(text: text, color: last.color, bold: last.bold, italic: last.italic);
      break;
    }
    tidy.removeLast();
  }
  return tidy;
}
