import 'package:fc_api/fc_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Служба истории: что она помнит и когда отменять нельзя
/// (`docs/spec/operation-history.md`, §7).
void main() {
  late OperationHistoryService history;
  late HistorySettings settings;

  setUp(() {
    settings = HistorySettings();
    history = OperationHistoryService(settings: () => settings);
  });

  /// Работа целиком: началась, рассказала и кончилась.
  void work(String runId, {String kind = 'file.copy', List<JournalEntry> journal = const [], String? obstacle}) {
    history.begin(runId, kind: kind);
    history.did(runId, journal, obstacle: obstacle);
    history.ended(runId, OperationOutcome.done);
  }

  test('новые записи идут первыми', () {
    work('run#1');
    work('run#2', kind: 'file.move');

    expect(history.all.first.kind, 'file.move');
    expect(history.last!.runId, 'run#2');
  });

  test('отменить можно то, что что-то сделало', () {
    work('run#1', journal: const [Created('/dest/a.txt', kind: EntryKind.file)]);

    expect(history.undoObstacle, isNull);
    expect(history.last!.canUndo, isTrue);
  });

  test('ничего не делали — отменять нечего, и это говорится словами', () {
    expect(history.undoObstacle, 'nothing to undo');

    work('run#1');
    expect(history.undoObstacle, 'this work changed nothing');
  });

  test('идущую работу не отменяют', () {
    history.begin('run#1', kind: 'file.copy');
    history.did('run#1', const [Created('/dest/a.txt', kind: EntryKind.file)]);

    expect(history.undoObstacle, 'the work is still running');
  });

  test('одна необратимая запись делает работу неотменимой целиком', () {
    // Перезапись возвращать неоткуда, и откатывать остальное поверх
    // утраченного значило бы возвращать мир, которого уже нет.
    work(
      'run#1',
      journal: const [Created('/dest/a.txt', kind: EntryKind.file), Destroyed('/dest/b.txt', reason: 'overwritten')],
    );

    expect(history.undoObstacle, 'overwritten');
  });

  test('причина работы сильнее её журнала', () {
    work('run#1', journal: const [Created('/dest/a.txt', kind: EntryKind.file)], obstacle: 'too many objects');

    expect(history.undoObstacle, 'too many objects');
  });

  test('отмена в списке видна, но отменять её не дают', () {
    work('run#1', journal: const [Created('/dest/a.txt', kind: EntryKind.file)]);
    work('run#2', kind: 'history.undo');

    expect(history.all.length, 2, reason: 'она изменила диск — человек должен её видеть');
    expect(history.undoTarget!.runId, 'run#1', reason: 'отменять отмену значило бы повторять');
  });

  test('отменённая запись пропускается, и очередь доходит до предыдущей', () {
    work('run#1', journal: const [Created('/dest/a.txt', kind: EntryKind.file)]);
    work('run#2', journal: const [Created('/dest/b.txt', kind: EntryKind.file)]);

    expect(history.undoTarget!.runId, 'run#2');
    history.markUndone('run#2');

    expect(history.undoTarget!.runId, 'run#1', reason: 'сделанного второй работой на диске уже нет');
    expect(history.all.length, 2, reason: 'из списка она никуда не делась');
  });

  test('необратимая запись сверху останавливает отмену, а не пропускается', () {
    work('run#1', journal: const [Created('/dest/a.txt', kind: EntryKind.file)]);
    work('run#2', journal: const [Destroyed('/dest/b.txt', reason: 'deleted permanently')]);

    // Перескок вернул бы мир, которого уже нет (§11).
    expect(history.undoTarget!.runId, 'run#2');
    expect(history.undoObstacle, 'deleted permanently');
  });

  test('глубина держит список коротким', () {
    settings.depth = 2;

    work('run#1');
    work('run#2');
    work('run#3');

    expect(history.all.length, 2);
    expect(history.all.last.runId, 'run#2', reason: 'самое старое забывается');
  });
}
