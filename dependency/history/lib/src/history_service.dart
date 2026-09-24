import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'history_settings.dart';

/// История файловых работ за сеанс (`docs/spec/operation-history.md`).
///
/// Между запусками не хранится: диск успевает измениться кем угодно, и
/// обещание «отменю вчерашнее» было бы враньём (§11).
class OperationHistoryService extends ChangeNotifier implements OperationHistory {
  OperationHistoryService({required this.settings});

  final HistorySettings Function() settings;

  final List<HistoryRecord> _records = [];

  /// Новые первыми: так их читают и так же показывает окно.
  @override
  List<HistoryRecord> get all => List.unmodifiable(_records);

  @override
  HistoryRecord? get last => _records.firstOrNull;

  @override
  String? get undoObstacle {
    final record = last;
    if (record == null) {
      return 'nothing to undo';
    }
    if (record.isRunning) {
      return 'the work is still running';
    }
    if (record.obstacle case final said?) {
      return said;
    }
    return record.journal.isEmpty ? 'this work changed nothing' : null;
  }

  @override
  void begin(String runId, {required String kind}) {
    _records.insert(0, HistoryRecord(runId: runId, kind: kind, at: DateTime.now()));
    _trim();
    notifyListeners();
  }

  @override
  void did(String runId, List<JournalEntry> entries, {String? obstacle}) {
    final record = _byId(runId);
    if (record == null) {
      return;
    }
    record.journal.addAll(entries);
    if (obstacle != null) {
      record.obstacle ??= obstacle;
    }
    // Одна необратимая запись делает работу неотменимой целиком: откатывать
    // остальное поверх утраченного значило бы возвращать мир, которого уже нет
    // (`docs/spec/operation-history.md`, §7).
    for (final entry in entries) {
      if (entry is Destroyed) {
        record.obstacle ??= entry.reason;
      }
    }
    notifyListeners();
  }

  @override
  void ended(String runId, OperationOutcome outcome) {
    final record = _byId(runId);
    if (record == null) {
      return;
    }
    record.outcome = outcome;
    notifyListeners();
  }

  HistoryRecord? _byId(String runId) {
    for (final record in _records) {
      if (record.runId == runId) {
        return record;
      }
    }
    return null;
  }

  /// Глубина — настройка: помнить всё за долгий сеанс незачем, а журнал копии
  /// целого каталога занимает память.
  void _trim() {
    final depth = settings().depth;
    if (_records.length > depth) {
      _records.removeRange(depth, _records.length);
    }
  }
}
