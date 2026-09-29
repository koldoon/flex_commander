import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Место чтения переезжает вместе с видом: `F5` не отбрасывает в начало
/// документа (`docs/spec/markdown-viewer.md`, §8).
void main() {
  // Строки пронумерованы с нуля: 0 — заголовок, 2 — абзац, 4 — второй
  // заголовок, 6 — второй абзац.
  const notes = '# Раз\n\nПервый абзац.\n\n## Два\n\nВторой абзац.\n';

  MarkdownViewerScreen screenOf({bool formatted = true}) => MarkdownViewerScreen(
    entry: FileEntry(name: 'readme.md', kind: EntryKind.file, path: '/home/readme.md', size: notes.length),
    document: FcMarkdownDocument.parse(notes),
    settings: MarkdownViewerSettings(startFormatted: formatted),
    onSettingsChanged: () {},
  );

  test('в исходник уходят на строке того блока, что был сверху', () {
    final screen = screenOf()..noteTopBlock(2);

    screen.toggleFormat();

    expect(screen.formatted, isFalse);
    expect(screen.startLine, 4, reason: 'блок 2 — это «## Два» на пятой строке');

    screen.dispose();
  });

  test('обратно возвращаются на тот же блок', () {
    final screen = screenOf(formatted: false)..noteTopLine(5);

    screen.toggleFormat();

    expect(screen.formatted, isTrue);
    expect(screen.startBlock, 2, reason: 'пятая строка принадлежит заголовку «Два»');

    screen.dispose();
  });

  test('туда и обратно возвращает ровно туда, откуда ушли', () {
    final screen = screenOf()..noteTopBlock(3);

    screen.toggleFormat();
    screen.toggleFormat();

    expect(screen.startBlock, 3);

    screen.dispose();
  });

  test('не читали — место начальное, а не случайное', () {
    final screen = screenOf();

    screen.toggleFormat();

    expect(screen.startLine, 0);

    screen.dispose();
  });

  test('пустой документ переключается без падения', () {
    final screen = MarkdownViewerScreen(
      entry: FileEntry(name: 'empty.md', kind: EntryKind.file, path: '/home/empty.md', size: 0),
      document: FcMarkdownDocument.parse(''),
      settings: MarkdownViewerSettings(startFormatted: true),
      onSettingsChanged: () {},
    );

    expect(screen.toggleFormat, returnsNormally);

    screen.dispose();
  });
}
