import 'dart:convert';

import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поиск по документу: в свёрстанном — по видимому, в исходнике — по разметке.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;

  // Блоки: 0 заголовок, 1 абзац, 2 подзаголовок, 3 абзац, 4 врезка.
  const notes =
      '# Заголовок\n\n'
      'Первый абзац про дело.\n\n'
      '## Второй раздел\n\n'
      '**Жирное** слово здесь.\n\n'
      '```dart\nvoid main() {}\n```\n';

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/readme.md', content: utf8.encode(notes)),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<MarkdownViewerScreen> open() async {
    runtime.app.left.setCursorToName('readme.md');
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();

    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as MarkdownViewerScreen;
  }

  Future<void> find(String pattern) async {
    await runtime.commands.create(MarkdownViewer.findCommandId)!.executeWith({FcFindTextCommand.patternParam: pattern});
    await pumpEventQueue();
  }

  test('в свёрстанном находится видимый текст', () async {
    final screen = await open();

    await find('Жирное');

    expect(screen.finder.matchCount, greaterThan(0));
  });

  test('а разметка не находится: её на экране нет', () async {
    final screen = await open();

    await find('**');

    expect(screen.finder.matchCount, 0, reason: 'звёздочек человек не видит и искать их не просил');
  });

  test('найденное знает свой блок', () async {
    final screen = await open();

    await find('Жирное');

    // Третий абзац документа — четвёртый блок, считая с нуля.
    expect(screen.activeBlock, 3);
  });

  test('заголовок находится в своём блоке', () async {
    final screen = await open();

    await find('Второй раздел');

    expect(screen.activeBlock, 2);
  });

  test('во врезке кода тоже ищут', () async {
    final screen = await open();

    await find('void main');

    expect(screen.finder.matchCount, greaterThan(0));
    expect(screen.activeBlock, 4);
  });

  test('в исходнике ищут по разметке', () async {
    final screen = await open();
    runtime.commands.dispatch(KeyCombination.parse('F5'));
    await pumpEventQueue();
    expect(screen.formatted, isFalse);

    await find('**');

    expect(screen.finder.matchCount, greaterThan(0), reason: 'в исходнике звёздочки видны и искать их законно');
  });

  test('поиск доступен, пока показан документ', () async {
    await open();

    expect(runtime.commands.isExecutable(runtime.commands.find(MarkdownViewer.findCommandId)!), isTrue);
  });

  test('ничего не нашлось — блок не подсвечен', () async {
    final screen = await open();

    await find('такого слова здесь нет');

    expect(screen.finder.matchCount, 0);
    expect(screen.activeBlock, isNull);
  });
}
