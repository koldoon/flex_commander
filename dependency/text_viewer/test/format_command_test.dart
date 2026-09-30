import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// `F5` в показе текста: отформатированная копия или исходник.
///
/// Форматирует не показ: умение приносит модуль, а команда берёт из реестра
/// первого, кто взялся за этот файл (`docs/spec/formatters.md`, §3).
void main() {
  /// Одна строка на весь файл — ровно то, что кладёт машина и чего человеку не
  /// прочитать.
  const packed = '{"name":"Ада","tags":["раз","два"],"size":7}';
  const broken = '{\n  "a": 1,\n  "b": ,\n}';

  late AppRuntime runtime;

  Future<AppRuntime> appWith({List<FcModule>? modules}) async {
    final app = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/data.json', content: utf8.encode(packed)),
        FakeEntry.file('/home/broken.json', content: utf8.encode(broken)),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('просто текст')),
      ])..home = '/home',
      modules: modules ?? featureModules(),
    );
    await app.app.start();

    return app;
  }

  setUp(() async {
    runtime = await appWith();
  });

  Future<TextViewerScreen> openViewer(String name) async {
    runtime.app.left.setCursorToName(name);
    await (runtime.commands.create(ViewFileCommand.commandId)!).executeWith();

    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as TextViewerScreen;
  }

  /// Нажать `F5` и дождаться: запуск команды асинхронный.
  Future<void> pressF5() async {
    expect(runtime.commands.dispatch(KeyCombination.parse('F5')), isTrue);
    await Future<void>.delayed(Duration.zero);
  }

  group('клавиша', () {
    test('в показе текста за F5 стоит форматирование, а в панелях — своё', () async {
      // В панелях F5 — копирование. Привязка принадлежит экрану, и спора между
      // ними нет: контексты разные.
      expect(runtime.commands.commandFor(KeyCombination.parse('F5'))?.id, isNot(ToggleFormatCommand.commandId));

      await openViewer('data.json');

      expect(runtime.commands.commandFor(KeyCombination.parse('F5'))?.id, ToggleFormatCommand.commandId);
    });

    test('подпись говорит, что нажатие сделает сейчас', () async {
      final screen = await openViewer('data.json');
      final command = runtime.commands.find(ToggleFormatCommand.commandId)!;

      expect(command.label, 'Format');

      await pressF5();

      expect(screen.formatted, isTrue);
      expect(command.label, 'Raw');
    });
  });

  group('json', () {
    test('нажатие разворачивает одну строку в читаемый вид', () async {
      final screen = await openViewer('data.json');
      expect(screen.controller.lineCount, 1, reason: 'машинный json — одна строка');

      await pressF5();

      expect(screen.formatted, isTrue);
      expect(screen.controller.lineCount, greaterThan(5));
      expect(screen.controller.text, contains('  "name": "Ада"'));
    });

    test('второе нажатие возвращает исходник', () async {
      final screen = await openViewer('data.json');

      await pressF5();
      await pressF5();

      expect(screen.formatted, isFalse);
      expect(screen.controller.text, packed);
    });

    test('файл не трогается: открытый заново, он такой, каким был', () async {
      final screen = await openViewer('data.json');
      await pressF5();
      expect(screen.controller.text, isNot(packed));

      // Показ вообще не умеет писать, и проверить это можно только со стороны
      // файла: закрыть и открыть заново.
      runtime.commands.dispatch(KeyCombination.parse('Esc'));
      await Future<void>.delayed(Duration.zero);
      final again = await openViewer('data.json');

      expect(again.controller.text, packed);
      expect(again.formatted, isFalse, reason: 'открывают как есть: вид не помнится между открытиями');
    });

    test('поиск после переключения ищет по показанному', () async {
      final screen = await openViewer('data.json');
      // Отступа в исходнике нет вовсе: он появляется только в отформатированном.
      await (runtime.commands.create(TextViewer.findCommandId)!).executeWith({
        FcFindTextCommand.patternParam: '  "size": 7',
      });
      expect(screen.finder.matchCount, 0);

      await pressF5();
      await (runtime.commands.create(TextViewer.findCommandId)!).executeWith({
        FcFindTextCommand.patternParam: '  "size": 7',
      });

      expect(screen.finder.matchCount, 1);
    });
  });

  group('отказ', () {
    test('кривой json называет строку и столбец, а на экране остаётся исходник', () async {
      final screen = await openViewer('broken.json');

      await pressF5();

      expect(screen.formatted, isFalse);
      expect(screen.controller.text, broken, reason: 'пустой экран не объясняет ничего');
      final said = runtime.app.toasts.current?.message ?? '';
      expect(said, contains('JSON'));
      expect(said, contains('line 3'), reason: 'сломалось на третьей строке');
      expect(said, contains('column'));
    });

    test('файл больше предела не форматируется, и сказано почему', () async {
      final screen = await openViewer('data.json');
      runtime.app.moduleSettings('fc.text_viewer').section(TextViewerSettings.new).maxFormatSize = 10;

      await pressF5();

      expect(screen.formatted, isFalse);
      expect(runtime.app.toasts.current?.message, contains('Too large to format'));
    });

    test('за текст без форматтера не берётся, и клавиша это показывает', () async {
      await openViewer('notes.txt');

      final command = runtime.commands.find(ToggleFormatCommand.commandId)!;

      // Приглушённая подпись в ряду — это и есть ответ: браться некому.
      expect(runtime.commands.isExecutable(command), isFalse);
    });

    test('в панелях команда невыполнима: показывать нечего', () {
      expect(runtime.commands.isExecutable(runtime.commands.find(ToggleFormatCommand.commandId)!), isFalse);
    });
  });

  group('без модуля форматтера', () {
    test('реестр пуст — F5 ничего не делает, и json открывается как раньше', () async {
      runtime = await appWith(modules: featureModules().where((module) => module.id != 'fc.json').toList());
      final screen = await openViewer('data.json');

      expect(runtime.app.formatters, isEmpty);
      expect(runtime.commands.isExecutable(runtime.commands.find(ToggleFormatCommand.commandId)!), isFalse);

      await Future<void>.delayed(Duration.zero);

      expect(screen.formatted, isFalse);
      expect(screen.controller.text, packed);
    });
  });

  group('форматтер', () {
    test('берётся за .json и не берётся за остальное', () {
      final spec = runtime.app.formatters.single;

      expect(spec.id, 'json');
      expect(
        spec.accepts(FileEntry(name: 'a.json', kind: EntryKind.file, path: '/home/a.json', size: 1), null),
        isTrue,
      );
      expect(spec.accepts(FileEntry(name: 'a.txt', kind: EntryKind.file, path: '/home/a.txt', size: 1), null), isFalse);
    });

    test('отступ — два пробела и перевод строки в конце', () {
      // Проверка со стороны потребителя: показ ничего к отформатированному не
      // приписывает и ничего из него не выкидывает.
      expect(runtime.app.formatters.single.format('{"a":1}'), '{\n  "a": 1\n}\n');
    });
  });
}
