import 'package:fc_api/fc_api.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Показ отформатированной копии: буфер один, файл не трогается, место чтения
/// переезжает долей от длины (`docs/spec/formatters.md`, §4).
void main() {
  TextViewerScreen screenOf(String text) => TextViewerScreen(
    entry: FileEntry(name: 'data.json', kind: EntryKind.file, path: '/home/data.json', size: text.length),
    text: text,
  );

  test('показанное меняется, а исходник остаётся на руках', () {
    final screen = screenOf('{"a":1}');

    screen.showFormatted((text) => '{\n  "a": 1\n}\n');

    expect(screen.formatted, isTrue);
    expect(screen.controller.text, contains('\n  "a": 1'));
    expect(screen.raw, '{"a":1}', reason: 'исходник нужен, чтобы вернуться и чтобы назвать место сбоя');

    screen.dispose();
  });

  test('второе нажатие возвращает исходник знак в знак', () {
    const raw = '{"a":1,"b":[2,3]}';
    final screen = screenOf(raw);

    screen.showFormatted((text) => 'что угодно\nв двух строках\n');
    screen.showRaw();

    expect(screen.formatted, isFalse);
    // Знак в знак: показ ничего не приписывает и ничего не теряет. Перевод
    // строки в конце — тоже знак.
    expect(screen.controller.text, raw);

    screen.dispose();
  });

  test('место чтения переезжает долей, а не строкой', () {
    // Десять строк исходника разворачиваются в сто. Строка 5 — половина
    // документа, и в отформатированном половина это строка 50, а не 5.
    final screen = screenOf(List.filled(10, 'строка').join('\n'))..noteTopLine(5);

    screen.showFormatted((text) => List.filled(100, 'строка').join('\n'));

    expect(screen.startLine, 50);

    screen.dispose();
  });

  test('место чтения не уезжает за последнюю строку', () {
    // Обратная сторона доли: из конца длинного вида в короткий.
    final screen = screenOf('одна строка')..noteTopLine(0);
    screen.showFormatted((text) => List.filled(100, 'строка').join('\n'));
    screen.noteTopLine(99);

    screen.showRaw();

    expect(screen.startLine, 0, reason: 'в исходнике всего одна строка');

    screen.dispose();
  });

  test('не читали — место начальное, а не случайное', () {
    final screen = screenOf(List.filled(10, 'строка').join('\n'));

    screen.showFormatted((text) => List.filled(100, 'строка').join('\n'));

    expect(screen.startLine, 0);

    screen.dispose();
  });

  test('отказ разбора оставляет исходник на экране', () {
    final screen = screenOf('{ поломано');

    expect(
      () => screen.showFormatted((text) => throw const FormatException('Unexpected character', '{ поломано', 2)),
      throwsFormatException,
    );

    expect(screen.formatted, isFalse, reason: 'состояния, которого нет, показ не принимает');
    expect(screen.controller.text, '{ поломано');

    screen.dispose();
  });

  test('форматируется один раз, а не на каждое нажатие', () {
    var calls = 0;
    final screen = screenOf('{"a":1}');
    String format(String text) {
      calls++;

      return '{\n  "a": 1\n}\n';
    }

    screen.showFormatted(format);
    screen.showRaw();
    screen.showFormatted(format);

    expect(calls, 1, reason: 'посчитанное лежит в памяти показа: вернуться к нему ничего не стоит');

    screen.dispose();
  });

  test('повторное нажатие в том же виде ничего не делает', () {
    final screen = screenOf('{"a":1}');

    screen.showRaw();

    expect(screen.formatted, isFalse);
    expect(screen.controller.text, '{"a":1}');

    screen.dispose();
  });

  test('пустой текст переключается без падения', () {
    final screen = screenOf('');

    expect(() => screen.showFormatted((text) => '{}\n'), returnsNormally);
    expect(screen.startLine, 0);

    screen.dispose();
  });
}
