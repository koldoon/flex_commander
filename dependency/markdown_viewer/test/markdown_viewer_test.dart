import 'dart:convert';

import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Markdown в собранном приложении: `F3` открывает документ, а не разметку.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;

  const notes = '# Заголовок\n\nАбзац про дело.\n\n```dart\nvoid main() {}\n```\n';

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/readme.md', content: utf8.encode(notes)),
        FakeEntry.file('/home/plain.txt', content: utf8.encode('просто текст')),
        // Имя обещает разметку, а внутри двоичное.
        FakeEntry.file('/home/fake.md', content: [0, 1, 2, 3, 0, 5]),
        // Больше предела по умолчанию (полмегабайта).
        FakeEntry.file('/home/huge.md', content: List<int>.filled(600 * 1024, 65)),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  /// Открывает то, что под курсором, — тем же путём, каким это делает `F3`.
  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  ViewportState? shown() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  group('чем открывается', () {
    test('`.md` открывает просмотрщик markdown, а не текстовый', () async {
      await view('readme.md');

      expect(shown(), isA<MarkdownViewerScreen>());
    });

    test('обычный текст по-прежнему открывает текстовый: реестр не перепутал', () async {
      await view('plain.txt');

      expect(shown(), isA<TextViewerScreen>());
    });

    test('документ разобран на блоки, а не оставлен строкой', () async {
      await view('readme.md');

      final screen = shown()! as MarkdownViewerScreen;
      // Заголовок, абзац и врезка.
      expect(screen.document.length, 3);
      expect(screen.document.source, notes);
    });

    test('двоичное под именем `.md` уходит дальше по очереди', () async {
      await view('fake.md');

      expect(shown(), isNot(isA<MarkdownViewerScreen>()));
    });
  });

  group('свёрстано и исходник', () {
    test('по умолчанию свёрстано', () async {
      await view('readme.md');

      expect((shown()! as MarkdownViewerScreen).formatted, isTrue);
    });

    test('F5 переключает туда и обратно', () async {
      await view('readme.md');
      final screen = shown()! as MarkdownViewerScreen;

      expect(runtime.commands.dispatch(KeyCombination.parse('F5')), isTrue);
      await pumpEventQueue();
      expect(screen.formatted, isFalse);

      expect(runtime.commands.dispatch(KeyCombination.parse('F5')), isTrue);
      await pumpEventQueue();
      expect(screen.formatted, isTrue);
    });

    test('выбор запоминается: `F5` не нажимают на каждом документе', () async {
      await view('readme.md');
      runtime.commands.dispatch(KeyCombination.parse('F5'));
      await pumpEventQueue();

      // Закрыли и открыли снова — вид остался тем, который выбрали.
      runtime.app.view.popViewportContent(ViewportPosition.fullscreen);
      await view('readme.md');

      expect((shown()! as MarkdownViewerScreen).formatted, isFalse);
    });

    test('подпись команды говорит, что клавиша сделает сейчас', () async {
      await view('readme.md');
      final command = runtime.commands.find(ToggleMarkdownFormatCommand.commandId)!;

      expect(command.label, 'Raw');

      runtime.commands.dispatch(KeyCombination.parse('F5'));
      await pumpEventQueue();

      expect(command.label, 'Format');
    });
  });

  group('предел', () {
    test('слишком большой документ не открывается свёрстанным', () async {
      await view('huge.md');

      // Показывать кусок и называть его документом — значит врать о
      // содержимом; поэтому отказ, а не начало файла.
      expect(shown(), isNot(isA<MarkdownViewerScreen>()));
    });

    test('а `docs/roadmap.md` по размеру проходит: предел выбран под него', () {
      // Треть мегабайта — предел полмегабайта.
      expect(350 * 1024, lessThan(MarkdownViewerSettings.defaultMaxFileSize));
    });
  });
}
