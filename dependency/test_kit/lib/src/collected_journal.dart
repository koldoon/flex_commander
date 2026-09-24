import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Журнал, который всё запоминает, — для проверок.
///
/// Настоящий живёт в ядре, у него предел и отправка пачками
/// (`docs/spec/operation-history.md`, §5); здесь нужно только то, что работа в
/// него написала.
class CollectedJournal implements Journal {
  final List<JournalEntry> entries = [];

  /// Первая названная причина, по которой отменить будет нельзя.
  String? obstacle;

  @override
  bool get writes => true;

  @override
  void did(JournalEntry entry) => entries.add(entry);

  @override
  void cannotUndo(String reason) => obstacle ??= reason;

  /// Записи одного вида — так проверка читается короче.
  List<T> only<T extends JournalEntry>() => entries.whereType<T>().toList();

  /// Пути, которых журнал касается, — в том порядке, в каком они записаны.
  List<String> get paths => [
    for (final entry in entries)
      switch (entry) {
        Created(:final path) => path,
        Moved(:final to) => to,
        Trashed(:final to) => to,
        Destroyed(:final path) => path,
      },
  ];
}
