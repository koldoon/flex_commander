import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';

/// Куда работа складывает свершившееся — по ходу дела, а не в конце.
///
/// Приёмником, а не замыканием: у него живёт предел, и движку переноса не
/// нужно знать ни про пачки, ни про границу
/// (`docs/spec/operation-history.md`, §4).
abstract interface class Journal {
  /// Пишут ли в него вообще: ложь — журнала не ведут или он переполнен.
  ///
  /// Спрашивают там, где запись стоит работы: собрать путь, прочитать размер.
  bool get writes;

  void did(JournalEntry entry);

  /// Почему отменить эту работу будет нельзя — словами. Первая причина и
  /// остаётся: их бывает несколько, а человеку нужна одна.
  void cannotUndo(String reason);

  /// Журнала не ведут вовсе — и это умолчание.
  static const Journal none = _Silent();
}

class _Silent implements Journal {
  const _Silent();

  @override
  bool get writes => false;

  @override
  void did(JournalEntry entry) {}

  @override
  void cannotUndo(String reason) {}
}

/// Вид записи по узлу — тем же правилом, каким его называет `entryValueOf`.
EntryKind journalKindOf(FsNode node) => switch (node) {
  DirectoryNode() => EntryKind.directory,
  LinkNode() => EntryKind.link,
  _ => EntryKind.file,
};

/// Дата изменения узла; null — у этого вида её нет.
///
/// Ею отмена сверяет, не правили ли файл с тех пор: у каталога сверять нечего,
/// и спрашивать её там незачем.
DateTime? journalModifiedOf(FsNode node) => node is FileNode ? node.modified : null;

/// Путь объекта, который ляжет в этот каталог под этим именем.
///
/// Показываемый, как и всё в журнале: только такую строку можно разобрать
/// заново (`docs/spec/operation-history.md`, §3).
String journalPathIn(DirectoryNode directory, String name) {
  final base = directory.displayPath;
  return base.endsWith('/') ? '$base$name' : '$base/$name';
}
