import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Корзина рассказывает, куда положила (`docs/spec/operation-history.md`, §3).
void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/docs/notes.txt', size: 20),
    ]);
  });

  Future<FsNode> nodeAt(String path) async => (await provider.resolvePath().run(path))!;

  test('объект переезжает в корзину, а не пропадает', () async {
    final landed = await provider.trashEntry(await nodeAt('/home/notes.txt'));

    expect(landed, isNotNull);
    expect(landed!.pathString, '/.Trash/notes.txt');
    expect(await provider.resolvePath().run('/.Trash/notes.txt'), isNotNull, reason: 'его можно вернуть');
    expect(await provider.resolvePath().run('/home/notes.txt'), isNull);
  });

  test('одноимённое разводится суффиксом, и узел говорит каким', () async {
    await provider.trashEntry(await nodeAt('/home/notes.txt'));
    final second = await provider.trashEntry(await nodeAt('/home/docs/notes.txt'));

    expect(second!.pathString, '/.Trash/notes 2.txt', reason: 'первое имя уже занято');
    expect(await provider.resolvePath().run('/.Trash/notes.txt'), isNotNull, reason: 'первое на месте');
  });

  test('каталог уезжает со всем, что под ним', () async {
    final landed = await provider.trashEntry(await nodeAt('/home/docs'));

    expect(landed!.pathString, '/.Trash/docs');
    expect(await provider.resolvePath().run('/.Trash/docs/notes.txt'), isNotNull);
  });

  test('корзины нет — ответ пустой, и удалять будет движок', () async {
    provider.hasTrash = false;

    expect(await provider.trashEntry(await nodeAt('/home/notes.txt')), isNull);
    expect(await provider.resolvePath().run('/home/notes.txt'), isNotNull, reason: 'ничего не тронуто');
  });
}
