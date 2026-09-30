import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Alt-Shift-F` в редакторе: форматирование — это правка.
///
/// Документ становится изменённым, возвращает его обычная отмена, а кривой
/// документ не трогается вовсе (`docs/spec/formatters.md`, §5).
void main() {
  const packed = '{"name":"Ада","tags":["раз","два"],"size":7}';
  const pretty = '{\n  "a": 1\n}\n';
  const broken = '{\n  "a": 1,\n  "b": ,\n}';

  late AppRuntime runtime;
  late InMemoryContentProvider disk;

  setUp(() async {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/data.json', content: utf8.encode(packed)),
      FakeEntry.file('/home/pretty.json', content: utf8.encode(pretty)),
      FakeEntry.file('/home/broken.json', content: utf8.encode(broken)),
      FakeEntry.file('/home/notes.txt', content: utf8.encode('просто текст')),
    ])..home = '/home';
    runtime = await testApp(provider: disk, modules: featureModules());
    await runtime.app.start();
  });

  Future<EditorScreen> edit(String name) async {
    runtime.app.left.setCursorToName(name);
    await (runtime.commands.create(EditFileCommand.commandId)!).executeWith();

    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as EditorScreen;
  }

  /// Нажать `Alt-Shift-F` и дождаться: запуск команды асинхронный.
  Future<void> press() async {
    expect(runtime.commands.dispatch(KeyCombination.parse('Alt-Shift-F')), isTrue);
    await pumpEventQueue();
  }

  Future<String> contentOf(String path) async {
    final node = (await disk.resolvePath().run(path))!;
    final chunks = await (await disk.openRead(node)).toList();

    return utf8.decode(chunks.expand((chunk) => chunk).toList());
  }

  group('клавиша', () {
    test('Alt-Shift-F принадлежит редактору, а в панелях за ней никого', () async {
      expect(runtime.commands.commandFor(KeyCombination.parse('Alt-Shift-F')), isNull);

      await edit('data.json');

      expect(runtime.commands.commandFor(KeyCombination.parse('Alt-Shift-F'))?.id, FormatDocumentCommand.commandId);
    });

    test('подпись постоянная: клавиша делает одно дело, а не переключает', () async {
      await edit('data.json');
      final command = runtime.commands.find(FormatDocumentCommand.commandId)!;

      expect(command.label, 'Format');

      await press();

      expect(command.label, 'Format', reason: 'это правка, а не два вида одного текста');
    });
  });

  group('правка', () {
    test('документ становится отформатированным и несохранённым', () async {
      final screen = await edit('data.json');
      expect(screen.modified, isFalse);

      await press();

      expect(screen.controller.text, contains('\n  "name": "Ада"'));
      // В заголовке появляется знак несохранённого, и выход предложит сохранить:
      // форматирование ведёт себя как правка, потому что правка и есть.
      expect(screen.modified, isTrue);
    });

    test('обычная отмена возвращает как было', () async {
      final screen = await edit('data.json');
      // До правки отменять нечего — иначе проверка ниже ничего бы не значила.
      expect(screen.controller.canUndo, isFalse);

      await press();

      expect(screen.controller.canUndo, isTrue, reason: 'замена легла в историю контроллера');
      screen.controller.undo();

      expect(screen.controller.text, packed);
      expect(screen.modified, isFalse, reason: 'вернулись к тому, что в файле');
    });

    test('отмена возвращает к набранному, а не перескакивает через него', () async {
      // Форматирование — **отдельный** шаг истории. Ляг оно поверх последнего,
      // одна `Cmd-Z` отменила бы заодно и то, что человек набрал до него.
      final screen = await edit('data.json');
      screen.controller.text = '{"b":2}';

      await press();
      screen.controller.undo();

      expect(screen.controller.text, '{"b":2}');
    });

    test('файл на диске не меняется, пока не сохранили', () async {
      await edit('data.json');

      await press();

      expect(await contentOf('/home/data.json'), packed);
    });

    test('форматируется показанное с правками, а не то, что лежит в файле', () async {
      final screen = await edit('data.json');
      screen.controller.text = '{"b":2}';

      await press();

      expect(screen.controller.text, '{\n  "b": 2\n}\n');
    });

    test('уже отформатированный документ не трогается, и сказано об этом', () async {
      final screen = await edit('pretty.json');

      await press();

      expect(screen.controller.text, pretty);
      expect(screen.modified, isFalse, reason: 'пустая правка пометила бы файл несохранённым ни за что');
      // И отмене не достаётся шага, который ничего не менял: следующая `Cmd-Z`
      // должна отменять работу человека, а не нажатие впустую.
      expect(screen.controller.canUndo, isFalse);
      expect(runtime.app.toasts.current?.message, 'Already formatted');
    });
  });

  group('отказ', () {
    test('кривой документ остаётся как есть, а отказ называет место', () async {
      final screen = await edit('broken.json');

      await press();

      expect(screen.controller.text, broken, reason: 'подменить кривое на «как получилось» значит потерять работу');
      expect(screen.modified, isFalse);
      final said = runtime.app.toasts.current?.message ?? '';
      expect(said, contains('JSON'));
      expect(said, contains('line 3'));
    });

    test('за текст без форматтера не берётся', () async {
      await edit('notes.txt');

      expect(runtime.commands.isExecutable(runtime.commands.find(FormatDocumentCommand.commandId)!), isFalse);
    });

    test('в файле только для чтения форматировать нечего', () async {
      final screen = EditorScreen(
        entry: FileEntry(name: 'data.json', kind: EntryKind.file, path: '/home/data.json', size: packed.length),
        file: const TextFile(text: packed, lineBreak: LineBreak.lf),
        wordWrap: false,
        readOnly: true,
      );
      runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, screen);

      // Правка в нём не сохранится, а помеченный несохранённым документ, который
      // нельзя записать, — обещание того, чего не будет.
      expect(runtime.commands.isExecutable(runtime.commands.find(FormatDocumentCommand.commandId)!), isFalse);

      screen.close();
    });

    test('документ больше предела не форматируется, и сказано почему', () async {
      final screen = await edit('data.json');
      runtime.app.moduleSettings('fc.editor').section(EditorSettings.new).maxFormatSize = 10;

      await press();

      expect(screen.controller.text, packed);
      expect(screen.modified, isFalse);
      expect(runtime.app.toasts.current?.message, contains('Too large to format'));
    });

    test('в панелях команда невыполнима: править нечего', () {
      expect(runtime.commands.isExecutable(runtime.commands.find(FormatDocumentCommand.commandId)!), isFalse);
    });
  });

  group('без модуля форматтера', () {
    test('реестр пуст — клавиша ничего не делает, и документ остаётся как был', () async {
      runtime = await testApp(
        provider: disk,
        modules: featureModules().where((module) => module.id != 'fc.json').toList(),
      );
      await runtime.app.start();
      final screen = await edit('data.json');

      expect(runtime.app.formatters, isEmpty);
      expect(runtime.commands.isExecutable(runtime.commands.find(FormatDocumentCommand.commandId)!), isFalse);
      expect(screen.controller.text, packed);
    });
  });
}
