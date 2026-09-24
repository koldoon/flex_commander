import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Записи журнала — обычные значения (`docs/spec/operation-history.md`, §3).
void main() {
  /// Запись едет доводами работы отката словарём и возвращается собой.
  JournalEntry? thereAndBack(JournalEntry entry) => JournalEntry.fromMap(entry.toMap());

  test('созданное помнит, чем и каким оно было', () {
    final at = DateTime(2026, 9, 24, 14, 22);
    final back = thereAndBack(Created('/home/copy.txt', kind: EntryKind.file, size: 128, modified: at));

    expect(back, isA<Created>());
    final created = back! as Created;
    expect(created.path, '/home/copy.txt');
    expect(created.size, 128);
    expect(created.modified, at);
    expect(created.isDirectory, isFalse);
  });

  test('у каталога размера нет, и он не выдумывается', () {
    final back = thereAndBack(const Created('/home/docs', kind: EntryKind.directory)) as Created;

    expect(back.isDirectory, isTrue);
    expect(back.size, FileEntry.unknownSize, reason: 'сверять каталог по размеру нечем');
    expect(back.modified, isNull);
  });

  test('переезд помнит оба конца', () {
    final back = thereAndBack(const Moved(from: '/home/a.txt', to: '/home/docs/a.txt', kind: EntryKind.file)) as Moved;

    expect(back.from, '/home/a.txt');
    expect(back.to, '/home/docs/a.txt');
  });

  test('корзина помнит имя, которым объект там лёг', () {
    final back =
        thereAndBack(const Trashed(from: '/home/b.txt', to: '/.Trash/b 2.txt', kind: EntryKind.file)) as Trashed;

    expect(back.to, '/.Trash/b 2.txt', reason: 'по нему и возвращают');
  });

  test('необратимое помнит причину — её покажут человеку', () {
    final back = thereAndBack(const Destroyed('/home/c.txt', reason: 'overwritten')) as Destroyed;

    expect(back.reason, 'overwritten');
  });

  test('непонятая запись пропускается, а не роняет разбор', () {
    // Доводы работы приезжают значениями: чужое или испорченное здесь не повод
    // не отменить остальное.
    expect(JournalEntry.fromMap('не карта'), isNull);
    expect(JournalEntry.fromMap({'what': 'выдумка'}), isNull);
    expect(JournalEntry.fromMap({'what': 'created'}), isNull, reason: 'без пути отменять нечего');
    expect(JournalEntry.fromMap({'what': 'moved', 'from': '/a'}), isNull);
  });
}
