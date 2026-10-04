import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сжатое дерево в панели: строки цепочек, их подписи и курсор
/// (`docs/spec/panel-view-compact-tree.md`, §3–§5).
void main() {
  late InMemoryTreeProvider provider;
  late TestPanel panel;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/a'),
      FakeEntry.directory('/home/a/b'),
      FakeEntry.directory('/home/a/b/c'),
      FakeEntry.file('/home/a/b/c/x.txt'),
      FakeEntry.file('/home/a/b/c/y.txt'),
      FakeEntry.file('/home/z.txt'),
      FakeEntry.directory('/other'),
    ]);
    panel = testPanel(provider: provider, settings: PanelSettings.defaults('/home'));
    await panel.openPath('/home');
  });

  tearDown(() => panel.dispose());

  List<String> rows() => [for (final entry in panel.session.entries) '${'  ' * entry.level}${entry.label}'];

  FileEntry? current() {
    final index = panel.session.cursorIndex;
    final entries = panel.session.entries;
    return index >= 0 && index < entries.length ? entries[index] : null;
  }

  test('раскрыли каталог — цепочка встала одной строкой с подписью', () async {
    await panel.session.setRows(RowsKind.compactTree);
    expect(rows(), ['/', '  home', '    a', '    z.txt', '  other']);

    await panel.session.setExpanded('/home/a', expanded: true);

    expect(rows(), ['/', '  home', '    a/b/c', '      x.txt', '      y.txt', '    z.txt', '  other']);
    final chain = panel.session.entries.firstWhere((entry) => entry.chainHead.isNotEmpty);
    expect(chain.path, '/home/a/b/c', reason: 'адрес строки — самый глубокий каталог');
    expect(chain.chainHead, 'a/b');
    expect(chain.name, 'c');
  });

  test('курсор, стоявший на раскрытом каталоге, остаётся на строке цепочки, а не уходит к предку', () async {
    await panel.session.setRows(RowsKind.compactTree);
    panel.setCursorToName('a');
    expect(current()?.path, '/home/a');

    await panel.session.setExpanded('/home/a', expanded: true);

    // Строки `a` больше нет — она стала строкой `a/b/c`. Обычное дерево
    // поставило бы курсор на `home`.
    expect(current()?.label, 'a/b/c');
  });

  test('свернуть строку цепочки — свернуть самый глубокий каталог', () async {
    await panel.session.setRows(RowsKind.compactTree);
    await panel.session.setExpanded('/home/a', expanded: true);

    await panel.session.setExpanded('/home/a/b/c', expanded: false);

    expect(rows(), ['/', '  home', '    a/b/c', '    z.txt', '  other']);
  });

  test('из дерева в сжатое курсор стоит на том же объекте — строкой цепочки', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/a', expanded: true);
    await panel.session.setExpanded('/home/a/b', expanded: true);
    panel.setCursorToName('b');
    expect(current()?.path, '/home/a/b');

    await panel.session.setRows(RowsKind.compactTree);

    expect(current()?.path, '/home/a/b/c');
    expect(current()?.label, 'a/b/c');
  });

  test('обычное дерево подписей не знает', () async {
    await panel.session.setRows(RowsKind.compactTree);
    await panel.session.setExpanded('/home/a', expanded: true);

    await panel.session.setRows(RowsKind.tree);

    expect(panel.session.entries.every((entry) => entry.chainHead.isEmpty), isTrue);
    expect(rows(), containsAllInOrder(['    a', '      b', '        c', '          x.txt']));
  });
}
