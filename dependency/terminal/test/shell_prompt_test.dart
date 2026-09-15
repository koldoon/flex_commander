import 'package:fc_terminal/fc_terminal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Приглашение снимается с экрана готовым (`docs/spec/shell-prompt.md`, §4).
///
/// Настоящим терминалом, а не подставкой: разбирать последовательности —
/// его работа, и подставка подтвердила бы любую ошибку в том, как мы их читаем.
void main() {
  /// Терминал, которому уже что-то написали, и место, откуда снимать.
  (Terminal, int, int) terminalAt(String written, {int width = 80}) {
    final terminal = Terminal(maxLines: 100);
    terminal.resize(width, 24);
    terminal.write(written);
    return (terminal, terminal.buffer.absoluteCursorY, terminal.buffer.cursorX);
  }

  ShellPrompt readFrom(Terminal terminal, int line, int column) => readShellPrompt(
    terminal.buffer,
    startLine: line,
    startColumn: column,
    endLine: terminal.buffer.absoluteCursorY,
    endColumn: terminal.buffer.cursorX,
  );

  test('простое приглашение снимается целиком', () {
    final (terminal, line, column) = terminalAt('');
    terminal.write(r'koldoon@cray:/tmp$ ');

    final prompt = readFrom(terminal, line, column);

    expect(prompt.lastText, r'koldoon@cray:/tmp$');
    expect(prompt.lines.length, 1);
  });

  test('цвета приезжают теми же числами, какими их хранит терминал', () {
    final (terminal, line, column) = terminalAt('');
    // Зелёный (`SGR 32`), потом обычный.
    terminal.write('\x1b[32m/tmp\x1b[0m \$ ');

    final runs = readFrom(terminal, line, column).lastLine;

    expect(runs.length, greaterThanOrEqualTo(2));
    expect(runs.first.text, '/tmp');
    expect(runs.first.color, isNot(runs.last.color), reason: 'первый кусок покрашен, второй — нет');
    expect(runs.last.text.trim(), r'$');
  });

  test('жирное и наклонное сохраняются, подчёркивание — нет', () {
    final (terminal, line, column) = terminalAt('');
    terminal.write('\x1b[1mbold\x1b[0m\x1b[3mitalic\x1b[0m\x1b[4munder\x1b[0m');

    final runs = readFrom(terminal, line, column).lastLine;

    expect(runs.firstWhere((run) => run.text == 'bold').bold, isTrue);
    expect(runs.firstWhere((run) => run.text == 'italic').italic, isTrue);
    final under = runs.firstWhere((run) => run.text == 'under');
    expect(under.bold, isFalse);
    expect(under.italic, isFalse);
  });

  test('соседние ячейки одного вида собираются в один кусок', () {
    final (terminal, line, column) = terminalAt('');
    terminal.write('ровная строка одного цвета');

    expect(readFrom(terminal, line, column).lastLine.length, 1);
  });

  test('перенос по краю экрана сшивается обратно', () {
    // Приглашение длиннее ширины: терминал перенёс его, но строка приглашения
    // от этого не стала двумя.
    final (terminal, line, column) = terminalAt('', width: 20);
    terminal.write('0123456789' * 3);

    final prompt = readFrom(terminal, line, column);

    expect(prompt.lines.length, 1, reason: 'перенос — не новая строка приглашения');
    expect(prompt.lastText, '0123456789' * 3);
  });

  test('многострочное приглашение: показывается последняя строка, целое остаётся', () {
    final (terminal, line, column) = terminalAt('');
    terminal.write('первая строка\r\n\$ ');

    final prompt = readFrom(terminal, line, column);

    expect(prompt.lines.length, 2);
    expect(prompt.lastText, r'$');
    expect(prompt.text, contains('первая строка'));
  });

  test('приглашения не было — снимать нечего', () {
    final (terminal, line, column) = terminalAt(r'$ ');

    expect(readFrom(terminal, line, column).isEmpty, isTrue);
  });

  test('хвостовые пробелы не считаются частью приглашения', () {
    final (terminal, line, column) = terminalAt('');
    terminal.write(r'$    ');

    expect(readFrom(terminal, line, column).lastText, r'$');
  });
}
