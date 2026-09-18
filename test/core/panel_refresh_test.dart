import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тихое перечитывание списка: он растёт сам, а курсор не трогают
/// (`docs/spec/panel-node-list.md`).
void main() {
  test('одинаковые имена не уводят курсор при перечитывании', () async {
    // Живая беда 18 сентября 2026: в находках имена повторяются сотнями —
    // `typescript/loc/lcl/PTB` лежит в каждом `node_modules`, — и перечитывание
    // звало курсор **по имени**. Он уходил на первую такую строку, следующая
    // пачка возвращала его назад, и панель мерцала между двумя местами.
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/a'),
      FakeEntry.file('/home/a/PTB', size: 1),
      FakeEntry.directory('/home/b'),
      FakeEntry.file('/home/b/PTB', size: 1),
    ])..home = '/home';

    // Деревом: тёзки видны разом — ровно как в списке находок.
    final panel = testPanel(
      provider: provider,
      settings: PanelSettings(path: '/home', expanded: ['/', '/home', '/home/a', '/home/b']),
    );
    addTearDown(panel.dispose);
    await panel.openPath('/home');
    await panel.showRows(RowsKind.tree);
    await Future<void>.delayed(Duration.zero);

    final twins = [
      for (var i = 0; i < panel.entries.length; i++)
        if (panel.entries[i].name == 'PTB') i,
    ];
    expect(twins, hasLength(2), reason: 'стенд ни о чём без тёзок в одном списке');

    // Курсор — на **втором** тёзке: первый и есть тот, к кому уводило.
    panel.setCursorIndex(twins.last);
    await Future<void>.delayed(Duration.zero);
    final was = panel.currentEntry!.path;
    expect(was, '/home/b/PTB');

    // Сторожим **каждое** опубликованное состояние, а не только последнее:
    // мерцало именно промежуточное — курсор уходил к тёзке и возвращался, а
    // вид честно подматывался к обоим.
    final seen = <String?>[];
    panel.addListener(() => seen.add(panel.currentEntry?.path));

    // Список перечитан сам по себе — как при растущих находках.
    await panel.session.refreshRows();
    await Future<void>.delayed(Duration.zero);

    expect(panel.currentEntry?.path, was, reason: 'курсор остался на своей строке');
    expect(seen, everyElement(anyOf(isNull, was)), reason: 'и ни на миг не уходил к тёзке');
  });
}
