import 'dart:async';
import 'dart:convert';

import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_editor/fc_editor.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Провайдер, у которого чтение файла можно задержать.
///
/// Ради этого всё и затевалось: на медленном источнике между `F4` и появлением
/// редактора проходят секунды, и проверять надо ровно то, что происходит в это
/// время.
class _SlowProvider extends InMemoryContentProvider {
  _SlowProvider(super.entries);

  final Completer<void> gate = Completer<void>();

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final source = await super.openRead(node, offset: offset);
    return () async* {
      await gate.future;
      yield* source;
    }();
  }
}

/// Открытие файла на правку: пока читается, видно, что читается, и это можно
/// бросить.
void main() {
  late AppRuntime runtime;
  late _SlowProvider disk;

  setUp(() async {
    disk = _SlowProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a-notes.txt', content: utf8.encode('раз\nдва')),
      FakeEntry.file('/home/b-other.txt', content: utf8.encode('прочее')),
    ])..home = '/home';
    runtime = await testApp(provider: disk, modules: featureModules());
    await runtime.app.start();
  });

  /// Приложение на экране, курсор на файле, `F4` нажата — но чтение висит.
  Future<void> startOpening(WidgetTester tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.left.setCursorToName('a-notes.txt');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.pump();
  }

  EditorScreen? editor() {
    final screen = runtime.app.view.contentAt(ViewportPosition.fullscreen);
    return screen is EditorScreen ? screen : null;
  }

  /// Отпустить чтение и дать ему дойти до конца.
  ///
  /// Через `runAsync`: `pump` крутит поддельное время, а поток чтения идёт по
  /// настоящему циклу событий, и внутри подделки он не двигается вовсе.
  Future<void> finishReading(WidgetTester tester) async {
    await tester.runAsync(() async {
      if (!disk.gate.isCompleted) {
        disk.gate.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('пока файл читается, панель занята и говорит об этом', (tester) async {
    await startOpening(tester);

    expect(runtime.app.left.busy, isTrue);
    expect(runtime.app.left.statusText, 'Reading a-notes.txt…');
    // Список файлов на виду: читается один файл, а не каталог.
    expect(runtime.app.left.nodes, isNotEmpty);
    expect(editor(), isNull, reason: 'экрана ещё нет');

    await finishReading(tester);
  });

  testWidgets('пока читается, клавиши до команд не доходят', (tester) async {
    await startOpening(tester);
    final before = runtime.app.left.cursorIndex;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(runtime.app.left.cursorIndex, before, reason: 'курсор стоит, пока панель занята');

    await finishReading(tester);
  });

  testWidgets('дочиталось — экран открылся, занятость снята', (tester) async {
    await startOpening(tester);
    await finishReading(tester);

    expect(editor(), isNotNull);
    expect(editor()!.controller.text, 'раз\nдва');
    expect(runtime.app.left.busy, isFalse);
    expect(runtime.app.left.statusText, isNull);
  });

  testWidgets('Esc бросает чтение: экрана нет, панель свободна', (tester) async {
    await startOpening(tester);
    final cursor = runtime.app.left.cursorIndex;

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(editor(), isNull, reason: 'передумали — экран не открывается');
    expect(runtime.app.left.busy, isFalse);
    expect(runtime.app.left.statusText, isNull);
    expect(runtime.app.left.cursorIndex, cursor, reason: 'панель осталась там же, где была');
    // И молча: отмена — обычный ход дела, а не беда.
    expect(runtime.app.toasts.current, isNull);

    await finishReading(tester);
  });

  testWidgets('Tab уводит с занятой панели, и там всё работает', (tester) async {
    await startOpening(tester);
    expect(runtime.app.left.active, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(runtime.app.right.active, isTrue, reason: 'уйти с занятой панели можно всегда');

    // И на соседней курсор ходит: занятость — свойство панели, а не приложения.
    final before = runtime.app.right.cursorIndex;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(runtime.app.right.cursorIndex, isNot(before));

    await finishReading(tester);
  });

  testWidgets('второго чтения занятая панель не начинает', (tester) async {
    await startOpening(tester);

    final open = runtime.commands.find(EditFileCommand.commandId)!;
    expect(runtime.commands.isExecutable(open), isFalse);

    await finishReading(tester);
  });
}
