import 'package:fc_api/fc_api.dart';
import 'package:fc_archive/fc_archive.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Распаковать архив туда же, где он лежит (`docs/spec/archive-here.md`).
void main() {
  late InMemoryContentProvider disk;
  late AppController app;

  /// Архив с одним корневым узлом и архив с россыпью: правило про каталог
  /// проверяется на обоих (§3.1).
  List<FakeEntry> insideOne() => [
    FakeEntry.directory('/src'),
    FakeEntry.file('/src/app.dart', content: [1, 2]),
  ];

  List<FakeEntry> insideMany() => [
    FakeEntry.file('/readme.md', content: [3]),
    FakeEntry.file('/notes.txt', content: [4]),
  ];

  Future<void> start({required List<FakeEntry> Function() inside}) async {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/deep'),
      FakeEntry.file('/home/deep/nested.arc', content: [0]),
      FakeEntry.file('/home/box.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
      FakeEntry.directory('/other'),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/other'));
    app =
        (await testApp(
          provider: disk,
          modules: [const ArchiveHere()],
          backend: [const ArchiveHere(), FakeArchiveMount(inside)],
          settings: settings,
        )).app;
    await app.start();
  }

  Future<void> extract() async {
    final command = app.commands.create(ExtractHereCommand.commandId)!;
    await command.executeWith(const {});
    await pumpEventQueue();
  }

  bool executable() {
    final command = app.commands.create(ExtractHereCommand.commandId)!;
    return app.commands.isExecutable(command);
  }

  test('архив с россыпью внутри раскладывается в каталог по своему имени', () async {
    await start(inside: insideMany);
    app.left.setCursorToName('box.arc');

    await extract();

    expect(disk.entryAt('/home/box/readme.md'), isNotNull);
    expect(disk.entryAt('/home/box/notes.txt'), isNotNull);
    expect(disk.entryAt('/home/readme.md'), isNull, reason: 'двести файлов поверх соседей не рассыпаются');
  });

  test('архив с одним корневым узлом ложится как есть', () async {
    await start(inside: insideOne);
    app.left.setCursorToName('box.arc');

    await extract();

    expect(disk.entryAt('/home/src/app.dart'), isNotNull);
    expect(disk.entryAt('/home/box'), isNull, reason: 'лишнего каталога не заводится');
  });

  test('распакованное ложится рядом с архивом, а не в соседнюю панель', () async {
    await start(inside: insideOne);
    app.left.setCursorToName('box.arc');

    await extract();

    expect(disk.entryAt('/home/src'), isNotNull);
    expect(disk.entryAt('/other/src'), isNull, reason: 'соседняя панель тут ни при чём');
  });

  test('помеченные в разных каталогах архивы разъезжаются каждый к себе', () async {
    await start(inside: insideOne);
    // Дерево: помечаем архив в /home и архив в /home/deep.
    await app.left.showRows(RowsKind.tree);
    app.left.setExpanded('/home/deep', expanded: true);
    await pumpEventQueue();
    app.left.setMarks({'/home/box.arc', '/home/deep/nested.arc'}, by: MarkChange.person);
    await pumpEventQueue();

    await extract();

    expect(disk.entryAt('/home/src/app.dart'), isNotNull);
    expect(disk.entryAt('/home/deep/src/app.dart'), isNotNull, reason: 'каждый лёг рядом с собой');
  });

  test('без объявленных упаковщиков «Pack here» невыполнима', () async {
    // Приложение собрано без zip, tar и 7z: паковать нечем, и команда об этом
    // говорит прямо, а не показывает окно с пустым списком (§4).
    await start(inside: insideOne);
    app.left.setCursorToName('notes.txt');

    final command = app.commands.create(PackHereCommand.commandId)!;

    expect(app.commands.isExecutable(command), isFalse);
  });

  test('без архивных модулей «Extract here» остаётся, но невыполнима', () async {
    // Ни один формат не объявлен — ни одна строка не скажет о себе, что
    // раскрывается.
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/box.arc', content: [0]),
    ]);
    app =
        (await testApp(
          provider: disk,
          modules: [const ArchiveHere()],
          backend: [const ArchiveHere()],
          settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
        )).app;
    await app.start();
    app.left.setCursorToName('box.arc');

    final command = app.commands.create(ExtractHereCommand.commandId)!;

    expect(command, isNotNull, reason: 'команда объявлена и видна в палитре');
    expect(app.commands.isExecutable(command), isFalse, reason: 'а раскрывать нечего');
  });

  test('над обычным файлом команда невыполнима', () async {
    await start(inside: insideOne);
    app.left.setCursorToName('notes.txt');

    expect(executable(), isFalse);
  });

  test('над архивом команда выполнима', () async {
    await start(inside: insideOne);
    app.left.setCursorToName('box.arc');

    expect(executable(), isTrue);
  });
}
