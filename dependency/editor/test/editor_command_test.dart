import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Редактор как экран: открывается по F4, пишет обратно, спрашивает о
/// несохранённом.
///
/// На настоящем диске, а не на подставке: сохранение здесь — это временный
/// файл и переименование, и проверять их на подставке значило бы проверять
/// подставку.
void main() {
  late Directory temp;
  late AppRuntime runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_editor');
    final root = await temp.resolveSymbolicLinks();
    await File(p.join(root, 'notes.txt')).writeAsString('раз\nдва\n');
    await File(p.join(root, 'windows.txt')).writeAsString('раз\r\nдва\r\n');
    await File(p.join(root, 'binary.bin')).writeAsBytes([0xC3, 0x28, 0xFF, 0x00]);

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults(root), right: PanelSettings.defaults(root)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<void> edit(String name) async {
    runtime.app.left.setCursorToName(name);
    await (runtime.commands.create(EditFileCommand.commandId)!).execute();
  }

  EditorScreen? openEditor() {
    final screen = runtime.app.screens.active;
    return screen is EditorScreen ? screen : null;
  }

  String fileText(String name) => File(p.join(temp.path, name)).readAsStringSync();

  group('открытие', () {
    test('F4 ставит редактор поверх панелей', () async {
      await edit('notes.txt');

      expect(openEditor(), isNotNull);
      expect(openEditor()!.controller.text, 'раз\nдва\n');
      expect(runtime.app.screens.stack.map((screen) => screen.id), [Screens.files, EditorScreen.screenId]);
    });

    test('редактору нужен фокус — в отличие от просмотрщика', () async {
      await edit('notes.txt');

      expect(openEditor()!.takesFocus, isTrue);
    });

    test('не-текст на правку не открывается, и сказано почему', () async {
      await edit('binary.bin');

      expect(openEditor(), isNull);
      expect(runtime.app.toasts.current?.message, contains('UTF-8'));
    });
  });

  group('сохранение', () {
    test('пока не меняли — сохранять нечего', () async {
      await edit('notes.txt');

      expect(runtime.commands.isExecutable(runtime.commands.find(SaveFileCommand.commandId)!), isFalse);
    });

    test('правка уходит в файл', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'раз\nдва\nтри\n';

      expect(openEditor()!.modified, isTrue);
      await (runtime.commands.create(SaveFileCommand.commandId)!).execute();

      expect(fileText('notes.txt'), 'раз\nдва\nтри\n');
      expect(openEditor()!.modified, isFalse);
    });

    test('переводы строк остаются такими, какими были', () async {
      // Иначе правка одной строки приходит в чужой diff как весь файл.
      await edit('windows.txt');
      openEditor()!.controller.text = 'раз\nдва\nтри\n';

      await (runtime.commands.create(SaveFileCommand.commandId)!).execute();

      expect(File(p.join(temp.path, 'windows.txt')).readAsBytesSync(), utf8.encode('раз\r\nдва\r\nтри\r\n'));
    });

    test('временный файл после себя не оставляется', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'иначе';
      await (runtime.commands.create(SaveFileCommand.commandId)!).execute();

      final names = temp.listSync().map((entity) => p.basename(entity.path));
      expect(names.where((name) => name.contains('fc-save')), isEmpty);
    });
  });

  group('закрытие', () {
    test('без правок закрывается молча', () async {
      await edit('notes.txt');
      final close = runtime.commands.create(CloseEditorCommand.commandId)! as CloseEditorCommand;

      expect(close.hasDialog, isFalse);
      await close.execute();

      expect(runtime.app.screens.active?.id, Screens.files);
    });

    test('с правками спрашивает, а не теряет молча', () async {
      await edit('notes.txt');
      openEditor()!.controller.text = 'несохранённое';

      final close = runtime.commands.create(CloseEditorCommand.commandId)! as CloseEditorCommand;

      expect(close.hasDialog, isTrue);
      expect(close.dialogTitle, 'Unsaved changes');
      // Экран при этом ещё открыт: вопрос задан, ответа нет.
      expect(openEditor(), isNotNull);
    });
  });

  group('клавиши', () {
    test('в редакторе за F2 стоит сохранение, а не перенос строк', () async {
      await edit('notes.txt');

      expect(runtime.commands.commandFor(KeyCombination.parse('F2'))?.id, SaveFileCommand.commandId);
      expect(runtime.commands.commandFor(KeyCombination.parse('Esc'))?.id, CloseEditorCommand.commandId);
    });

    test('F9 прячет номера строк, не меняя подписи', () async {
      await edit('notes.txt');
      final numbers = runtime.commands.commandFor(KeyCombination.parse('F9'))!;

      // В редакторе номера включены: правя код, на строки ссылаются.
      expect(openEditor()!.showLineNumbers, isTrue);
      expect(numbers.label, 'Line Num');

      runtime.commands.dispatch(KeyCombination.parse('F9'));

      expect(openEditor()!.showLineNumbers, isFalse);
      // Подпись остаётся прежней: номера видно на самом экране.
      expect(runtime.commands.commandFor(KeyCombination.parse('F9'))!.label, 'Line Num');
      expect(runtime.app.toasts.current?.message, 'Show line numbers: Off');
    });

    test('номера строк помнятся между открытиями', () async {
      await edit('notes.txt');
      runtime.commands.dispatch(KeyCombination.parse('F9'));
      runtime.commands.dispatch(KeyCombination.parse('Esc'));

      await edit('notes.txt');

      expect(openEditor()!.showLineNumbers, isFalse);
    });

    test('панельные клавиши в редакторе молчат', () async {
      await edit('notes.txt');

      expect(runtime.commands.commandFor(KeyCombination.parse('F5')), isNull);
      expect(runtime.commands.commandFor(KeyCombination.parse('F3')), isNull);
    });
  });
}
