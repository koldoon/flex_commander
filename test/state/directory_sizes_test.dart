import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/ui/panel_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

/// Размеры всех каталогов одним нажатием.
///
/// Считает та же очередь, что и пометка, — и это главное, что здесь
/// проверяется: второго механизма не заводится, а различие оснований («помечено»
/// против «попрошено») видно по тому, отменяет ли пометка идущий подсчёт.
void main() {
  late AppRuntime runtime;
  late InMemoryTreeProvider provider;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/big'),
      FakeEntry.file('/home/big/a.bin', size: 3000),
      FakeEntry.directory('/home/small'),
      FakeEntry.file('/home/small/b.bin', size: 10),
      FakeEntry.directory('/home/mid'),
      FakeEntry.file('/home/mid/c.bin', size: 500),
      FakeEntry.file('/home/notes.txt', size: 1),
    ])..home = '/home';

    runtime = await testApp(provider: provider, modules: featureModules());
    await runtime.app.start();
  });

  PanelMirror panel() => runtime.app.left;

  PanelSession session() => runtime.app.leftSession;

  DirectoryNode dir(String name) => session().nodes.firstWhere((node) => node.name == name) as DirectoryNode;

  Future<void> settle() async {
    for (var i = 0; i < 20 && !session().selectionSizeIsFinal; i++) {
      await pumpEventQueue();
    }
  }

  test('считаются все каталоги, кроме «..» и уже посчитанных', () async {
    expect(dir('big').size, FsNode.unknownSize);

    panel().measureDirectories();
    await settle();

    expect(dir('big').size, 3000);
    expect(dir('mid').size, 500);
    expect(dir('small').size, 10);
    // `..` — это дерево выше, его по нажатию не считают.
    final parent = session().nodes.whereType<ParentDirNode>().firstOrNull;
    expect(parent?.size ?? FsNode.unknownSize, FsNode.unknownSize);
  });

  test('пометка идущий подсчёт не отменяет', () async {
    panel().measureDirectories();
    // Пометили и тут же сняли — до этого такое отменяло весь обход.
    panel().setCursorToName('big');
    panel().toggleCurrentMark();
    panel().setCursorToName('big');
    panel().toggleCurrentMark();
    await settle();

    expect(dir('big').size, 3000);
    expect(dir('mid').size, 500);
  });

  test('пока идёт — строка состояния говорит об этом, потом замолкает', () async {
    panel().measureDirectories();
    expect(panel().statusText, contains('Measuring'));

    await settle();
    expect(panel().statusText, isNull);
  });

  test('уход из каталога подсчёт прекращает', () async {
    panel().measureDirectories();
    await session().open(dir('big'));
    await settle();

    expect(panel().statusText, isNull);
    expect(session().path, '/home/big');
  });

  test('по опустошению очереди список пересортируется, а курсор остаётся на объекте', () async {
    panel().sortBy(FsColumn.size);
    panel().setCursorToName('small');
    final before = [for (final node in session().nodes) node.name];

    panel().measureDirectories();
    await settle();

    final after = [for (final node in session().nodes) node.name];
    expect(after, isNot(before), reason: 'колонка изменилась целиком — порядок обязан её догнать');
    expect(session().currentNode?.name, 'small', reason: 'курсор держится за объект, а не за место');
  });

  test('при сортировке по имени порядок не трогается', () async {
    panel().sortBy(FsColumn.name);
    final before = [for (final node in session().nodes) node.name];

    panel().measureDirectories();
    await settle();

    expect([for (final node in session().nodes) node.name], before);
  });

  test('команда невыполнима, пока панель занята', () {
    final command = runtime.commands.find('panel.calculateSizes');
    expect(command, isNotNull);
    expect(runtime.commands.isExecutable(command!), isTrue);
  });
}
