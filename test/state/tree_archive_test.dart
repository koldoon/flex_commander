import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Архив в дереве — ветвь, которая монтируется
/// (`docs/spec/panel-view-tree.md`, §4б).
void main() {
  late ProviderRegistry registry;
  late TestPanel panel;

  /// Тест «закрытая панель» закрывает её сам, и второй раз закрывать нельзя.
  var closed = false;

  setUp(() async {
    final disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.arc', content: [0]),
      FakeEntry.file('/home/notes.txt', size: 3),
    ]);
    registry = ProviderRegistry(root: disk)..register(
      'arc',
      () => TaskOperation<FsNode, TreeProvider>(
        (op, host) async => InMemoryArchiveProvider([
          FakeEntry.directory('/inner'),
          FakeEntry.file('/inner/doc.txt', content: [1, 2, 3]),
          FakeEntry.file('/readme.md', content: [4]),
        ], host),
      ),
      extensions: {'arc'},
    );
    closed = false;
    panel = testPanel(provider: registry.root, registry: registry, settings: PanelSettings.defaults('/home'));
    await panel.openPath('/home');
    await panel.session.setRows(RowsKind.tree);
  });

  tearDown(() {
    if (!closed) {
      panel.dispose();
    }
  });

  List<String> namesOf() => panel.session.nodes.map((node) => node.name).toList();

  FsNode rowAt(String path) => panel.session.nodes.firstWhere((node) => node.pathString == path);

  test('архив обещает ветвь, не открываясь', () async {
    // Узнать, есть ли внутри что-нибудь, можно только открыв архив, а
    // открывать всё видимое ради знака — читать диск целиком. Поэтому «я
    // ветвь» архив говорит сам, а не через «что внутри».
    expect(rowAt('/home/archive.arc').mountsAsBranch, isTrue);
    expect(rowAt('/home/archive.arc').hasBranches, isNull, reason: 'внутрь не заглядывали');
    expect(registry.mounted, isEmpty, reason: 'знак сам по себе ничего не монтирует');
    expect(rowAt('/home/notes.txt').mountsAsBranch, isFalse, reason: 'обычный файл ветвью не притворяется');
  });

  test('раскрытый архив показывает своё содержимое ветвью', () async {
    await panel.session.setExpanded('/home/archive.arc', expanded: true);

    expect(namesOf(), containsAllInOrder(['archive.arc', 'inner', 'readme.md']));
    expect(rowAt('/home/archive.arc:arc:/inner').level, rowAt('/home/archive.arc').level + 1);
    expect(registry.mounted, hasLength(1), reason: 'раскрытие и есть монтирование');
  });

  test('свёрнутая ветвь отпускает архив', () async {
    await panel.session.setExpanded('/home/archive.arc', expanded: true);

    await panel.session.setExpanded('/home/archive.arc', expanded: false);
    await pumpEventQueue();

    expect(namesOf(), isNot(contains('readme.md')));
    expect(registry.mounted, isEmpty, reason: 'ветвь свернули — держать архив незачем');
  });

  test('закрытая панель архива не держит', () async {
    await panel.session.setExpanded('/home/archive.arc', expanded: true);

    panel.dispose();
    closed = true;
    await pumpEventQueue();

    expect(registry.mounted, isEmpty);
  });

  test('«раскрыть всё» архивы не открывает', () async {
    // У «раскрыть всё» нет естественного конца, а монтирование — чтение чужого
    // файла целиком: сотня архивов превратила бы одну клавишу в сотню
    // распаковок.
    await panel.session.setExpandedDeep('', expanded: true);

    expect(namesOf(), contains('archive.arc'));
    expect(namesOf(), isNot(contains('readme.md')));
    expect(registry.mounted, isEmpty);
  });

  test('панель внутри архива показывает дерево от диска', () async {
    // Живая находка: дерево собиралось от корня **архива**, наверху оказывался
    // его корень, и выйти было некуда — только историей.
    await panel.session.setRows(RowsKind.listing);
    panel.setCursorToName('archive.arc');
    await panel.session.enterRow(panel.session.currentNode);

    await panel.session.setRows(RowsKind.tree);

    expect(namesOf(), containsAllInOrder(['/', 'home', 'archive.arc', 'inner', 'readme.md']));
    expect(panel.session.currentNode?.pathString, '/home/archive.arc', reason: 'своей строки у корня архива нет');
    expect(panel.session.currentPath, '/home', reason: 'панель стоит там, где лежит строка под курсором');
  });

  group('архив с одними файлами внутри', () {
    late ProviderRegistry flatRegistry;
    late TestPanel flat;

    setUp(() async {
      final disk = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/flat.arc', content: [0]),
      ]);
      flatRegistry = ProviderRegistry(root: disk)..register(
        'arc',
        () => TaskOperation<FsNode, TreeProvider>(
          (op, host) async => InMemoryArchiveProvider([
            FakeEntry.file('/readme.md', content: [4]),
            FakeEntry.file('/notes.txt', content: [5]),
          ], host),
        ),
        extensions: {'arc'},
      );
      flat = testPanel(provider: flatRegistry.root, registry: flatRegistry, settings: PanelSettings.defaults('/home'));
      addTearDown(flat.dispose);
      await flat.openPath('/home');
      await flat.session.setRows(RowsKind.tree);
    });

    FsNode flatRow() => flat.session.nodes.firstWhere((node) => node.name == 'flat.arc');

    test('раскрытый архив знака раскрытия не теряет', () async {
      // Живая находка 23 сентября 2026: «раскрывается» спутали с «есть ли
      // внутри ветви». У архива с одними файлами второе ложно — и шеврон
      // пропадал ровно в тот миг, когда архив открыли.
      expect(flatRow().mountsAsBranch, isTrue);

      await flat.session.setExpanded('/home/flat.arc', expanded: true);

      expect(flat.session.nodes.map((node) => node.name), containsAllInOrder(['flat.arc', 'notes.txt']));
      expect(flatRow().mountsAsBranch, isTrue, reason: 'раскрытый архив остаётся ветвью');
      expect(flatRow().hasBranches, isFalse, reason: 'а вот своих ветвей внутри у него и правда нет');
    });

    test('свёрнутый архив открывается снова', () async {
      await flat.session.setExpanded('/home/flat.arc', expanded: true);
      await flat.session.setExpanded('/home/flat.arc', expanded: false);
      await pumpEventQueue();

      await flat.session.setExpanded('/home/flat.arc', expanded: true);

      expect(flat.session.nodes.map((node) => node.name), contains('readme.md'));
      expect(flatRegistry.mounted, hasLength(1), reason: 'аренду отпустили — архив монтируется заново');
    });
  });
}
