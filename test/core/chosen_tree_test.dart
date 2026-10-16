import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Выбранное деревом — откуда каждый объект (`docs/spec/trash-unavailable.md`,
/// §4а). Каталоги — настоящие узлы, а не достроенные по пути.
void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/storage'),
      FakeEntry.directory('/storage/music'),
      FakeEntry.directory('/storage/music/rock'),
      FakeEntry.file('/storage/music/rock/a.mp3', size: 1),
      FakeEntry.file('/storage/music/c.mp3', size: 1),
      FakeEntry.directory('/storage/video'),
      FakeEntry.directory('/storage/video/clips'),
      FakeEntry.directory('/storage/video/clips/2024'),
      FakeEntry.file('/storage/video/clips/2024/b.mkv', size: 1),
    ]);
  });

  Future<FsNode> at(String path) async => (await provider.resolvePath().run(path))!;

  List<String> labels(List<FileEntry> rows) => [for (final row in rows) '${'  ' * row.level}${row.label}'];

  test('корень — общий каталог, цепочки склеены, объекты не раскрыты', () async {
    final rows = chosenTreeRows([
      await at('/storage/music/rock/a.mp3'),
      await at('/storage/video/clips/2024/b.mkv'),
      await at('/storage/music/c.mp3'),
    ]);

    expect(labels(rows), [
      'storage',
      '  music',
      '    rock',
      '      a.mp3',
      '    c.mp3',
      '  video/clips/2024',
      '    b.mkv',
    ]);
    expect(rows.first.isOpen, isTrue);
    expect(rows.last.isOpen, isFalse);
    expect(rows[1].kind, EntryKind.directory, reason: 'каталог — настоящий узел');
  });

  test('у корня в голове — где он лежит', () async {
    final rows = chosenTreeRows([await at('/storage/music/rock/a.mp3'), await at('/storage/music/c.mp3')]);

    expect(rows.first.label, '/storage/music');
    expect(labels(rows), ['/storage/music', '  rock', '    a.mp3', '  c.mp3']);
  });

  test('пусто — строк нет', () {
    expect(chosenTreeRows(const []), isEmpty);
  });
}
