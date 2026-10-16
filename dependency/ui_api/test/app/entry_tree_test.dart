import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дерево из готовых строк — список удаляемого мимо корзины
/// (`docs/spec/trash-unavailable.md`, §4а).
void main() {
  FileEntry file(String path) {
    final slash = path.lastIndexOf('/');
    return FileEntry(
      name: path.substring(slash + 1),
      kind: EntryKind.file,
      path: path,
      directoryPath: path.substring(0, slash),
    );
  }

  List<String> labels(List<FileEntry> rows) => [for (final row in rows) '${'  ' * row.level}${row.label}'];

  test('корень — общий каталог, ветви — откуда объекты', () {
    final rows = entryTreeRows([
      file('/Volumes/Storage/music/rock/a.mp3'),
      file('/Volumes/Storage/video/clips/2024/b.mkv'),
      file('/Volumes/Storage/music/c.mp3'),
    ]);

    expect(labels(rows), [
      '/Volumes/Storage',
      '  music',
      '    rock',
      '      a.mp3',
      '    c.mp3',
      '  video/clips/2024',
      '    b.mkv',
    ]);
    expect(rows.first.isOpen, isTrue);
    expect(rows.last.isOpen, isFalse, reason: 'сам объект не раскрыт');
  });

  test('один объект — корнем его каталог', () {
    expect(labels(entryTreeRows([file('/Volumes/Storage/music/a.mp3')])), ['/Volumes/Storage/music', '  a.mp3']);
  });

  test('пусто — строк нет', () {
    expect(entryTreeRows(const []), isEmpty);
  });
}
