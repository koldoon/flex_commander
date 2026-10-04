import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Быстрый поиск в сжатом дереве: поглощённое имя находит строку цепочки
/// (`docs/spec/panel-view-compact-tree.md`, §7).
void main() {
  late AppRuntime runtime;

  Session panel() => runtime.app.left;
  FileEntry? cursor() => panel().currentEntry;
  bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

  void type(String text) {
    for (final character in text.split('')) {
      runtime.commands.dispatch(KeyCombination.parse(character));
    }
  }

  /// Дать ядру ответить: строки дерева приходят своим событием.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await pumpEventQueue();
    }
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/src'),
        FakeEntry.directory('/home/src/main'),
        FakeEntry.directory('/home/src/main/java'),
        FakeEntry.file('/home/src/main/java/App.java'),
        FakeEntry.file('/home/src/main/java/Util.java'),
        FakeEntry.file('/home/notes.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
    await panel().showRows(RowsKind.compactTree);
    await settle();
    panel().setExpanded('/home/src', expanded: true);
    await settle();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('поглощённое имя находит строку цепочки', () {
    expect(panel().entries.map((entry) => entry.label), contains('src/main/java'));

    press('Ctrl-S');
    type('ja');

    expect(cursor()?.label, 'src/main/java');
  });

  test('начало подписи — тоже', () {
    press('Ctrl-S');
    type('src/m');

    expect(cursor()?.label, 'src/main/java');
  });

  test('имя самой строки — как всегда', () {
    press('Ctrl-S');
    type('no');

    expect(cursor()?.name, 'notes.txt');
  });
}
