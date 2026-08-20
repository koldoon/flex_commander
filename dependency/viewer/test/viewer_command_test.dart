import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Просмотрщик как экран: открывается по F3, живёт своими клавишами, уходит
/// по Esc.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('раз\nдва\nтри')),
        FakeEntry.file('/home/big.log', size: 200 * 1024),
        FakeEntry.directory('/home/docs'),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    final command = runtime.commands.create(ViewFileCommand.commandId)!;
    await command.execute();
  }

  ViewerScreen? openViewer() {
    final screen = runtime.app.screens.active;
    return screen is ViewerScreen ? screen : null;
  }

  group('открытие', () {
    test('F3 ставит просмотрщик поверх панелей', () async {
      await view('notes.txt');

      expect(openViewer(), isNotNull);
      expect(openViewer()!.node.name, 'notes.txt');
      expect(openViewer()!.controller.text, 'раз\nдва\nтри');
      // Панели никуда не делись — они под ним.
      expect(runtime.app.screens.stack.map((screen) => screen.id), [Screens.files, ViewerScreen.screenId]);
    });

    test('каталог показывать нечем', () {
      runtime.app.left.setCursorToName('docs');
      final command = runtime.commands.find(ViewFileCommand.commandId)!;

      expect(runtime.commands.isExecutable(command), isFalse);
    });

    test('файл больше предела не открывается, и сказано почему', () async {
      await view('big.log');

      expect(openViewer(), isNull);
      // Назван и размер файла, и сам предел — видно, где его менять.
      expect(runtime.app.toasts.current?.message, contains('too large'));
      expect(runtime.app.toasts.current?.message, contains('200'));
      expect(runtime.app.toasts.current?.message, contains('100K'));
    });
  });

  group('клавиши просмотрщика', () {
    test('F2 переключает перенос и меняет подпись', () async {
      await view('notes.txt');
      final wrap = runtime.commands.commandFor(KeyCombination.parse('F2'))!;

      expect(wrap.label, 'Wrap');
      expect(openViewer()!.wordWrap, isFalse);

      runtime.commands.dispatch(KeyCombination.parse('F2'));

      expect(openViewer()!.wordWrap, isTrue);
      // Подпись говорит, что клавиша сделает **сейчас**.
      expect(runtime.commands.commandFor(KeyCombination.parse('F2'))!.label, 'Unwrap');
    });

    test('Esc закрывает и возвращает панели', () async {
      await view('notes.txt');

      runtime.commands.dispatch(KeyCombination.parse('Esc'));

      expect(openViewer(), isNull);
      expect(runtime.app.screens.active?.id, Screens.files);
    });

    test('F10 закрывает так же, как Esc', () async {
      await view('notes.txt');

      runtime.commands.dispatch(KeyCombination.parse('F10'));

      expect(runtime.app.screens.active?.id, Screens.files);
    });

    test('панельные клавиши в просмотрщике молчат', () async {
      await view('notes.txt');

      // Ни копирования из-под просмотрщика, ни второго просмотрщика поверх
      // первого.
      expect(runtime.commands.commandFor(KeyCombination.parse('F5')), isNull);
      expect(runtime.commands.commandFor(KeyCombination.parse('F3')), isNull);
      expect(runtime.commands.dispatch(KeyCombination.parse('F3')), isFalse);
      expect(runtime.app.screens.stack, hasLength(2));
    });

    test('в панелях за F2 стоит не просмотрщик', () {
      expect(runtime.commands.commandFor(KeyCombination.parse('F2'))?.label, isNot('Wrap'));
    });
  });

  group('настройки', () {
    test('перенос помнится между открытиями', () async {
      await view('notes.txt');
      runtime.commands.dispatch(KeyCombination.parse('F2'));
      runtime.commands.dispatch(KeyCombination.parse('Esc'));

      await view('notes.txt');

      expect(openViewer()!.wordWrap, isTrue);
    });

    test('предел лежит в разделе модуля', () {
      final settings = runtime.app.moduleSettings('fc.viewer').section(ViewerSettings.new);

      expect(settings.maxFileSize, ViewerSettings.defaultMaxFileSize);
      expect(settings.maxFileSize, 100 * 1024);
    });
  });
}
