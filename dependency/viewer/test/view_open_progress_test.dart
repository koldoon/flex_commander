import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Провайдер, у которого чтение файла можно задержать.
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

/// Открытие просмотрщика: та же повадка, что у редактора, — беда была одна.
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

  Future<void> pressF3(WidgetTester tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.left.setCursorToName('a-notes.txt');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
  }

  Future<void> finishReading(WidgetTester tester) async {
    await tester.runAsync(() async {
      if (!disk.gate.isCompleted) {
        disk.gate.complete();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  ViewportState? shown() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  testWidgets('пока файл читается, панель занята и говорит об этом', (tester) async {
    await pressF3(tester);

    expect(runtime.app.left.busy, isTrue);
    expect(runtime.app.left.statusText, 'Reading a-notes.txt…');
    expect(shown(), isNull);

    await finishReading(tester);
    expect(shown(), isNotNull);
    expect(runtime.app.left.busy, isFalse);
  });

  testWidgets('Esc бросает чтение: показа нет, панель свободна', (tester) async {
    await pressF3(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(shown(), isNull);
    expect(runtime.app.left.busy, isFalse);
    expect(runtime.app.left.statusText, isNull);

    await finishReading(tester);
  });

  testWidgets('быстрый просмотр панель занятой не делает', (tester) async {
    // По ней в это время водят курсором — ради чего его и открывают. Своё
    // «Reading …» он говорит сам, в той области, которую занял.
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.app.left.setCursorToName('a-notes.txt');
    await tester.pump();

    runtime.commands.dispatch(KeyCombination.parse('Shift-F3'));
    await tester.pump();

    expect(runtime.app.left.busy, isFalse, reason: 'курсор в ней должен ходить свободно');

    await finishReading(tester);
  });
}
