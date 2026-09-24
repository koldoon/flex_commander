import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

/// Что приложение сделало с файлами за сеанс — записями, новые первыми.
///
/// Служба необязательная: её приносит модуль истории. Нет его — `Application`
/// отвечает пустым полем, журнал не ведётся вовсе, а `Cmd-Z` не привязан ни к
/// чему (`docs/spec/operation-history.md`).
///
/// Пишет сюда **одно место** — то, через которое уходит всякая работа ядра:
/// оно знает и имя работы, и её журнал, и исход.
abstract interface class OperationHistory implements Listenable {
  List<HistoryRecord> get all;

  /// Последняя запись; null — ничего ещё не делали.
  HistoryRecord? get last;

  /// Почему последнюю запись отменить нельзя; null — можно.
  String? get undoObstacle;

  /// Работа началась.
  void begin(String runId, {required String kind});

  /// Работа рассказала, что сделала, — пачкой.
  void did(String runId, List<JournalEntry> entries, {String? obstacle});

  /// Работа кончилась — и вот чем.
  void ended(String runId, OperationOutcome outcome);
}

/// Одна работа в истории.
class HistoryRecord {
  HistoryRecord({required this.runId, required this.kind, required this.at});

  final String runId;

  /// Имя рода работы: `file.copy`, `file.remove`. Им она и называется — как
  /// именно, решает тот, кто показывает: перевод живёт на экране.
  final String kind;

  final DateTime at;

  /// Что работа сделала, в том порядке, в каком делала.
  final List<JournalEntry> journal = [];

  /// Почему отменить нельзя; null — ничего не мешает.
  ///
  /// Причина приезжает либо от самой работы (слияние, переполнение), либо
  /// находится в журнале: одна необратимая запись делает работу неотменимой
  /// целиком (`docs/spec/operation-history.md`, §7).
  String? obstacle;

  /// Чем кончилась; null — ещё идёт.
  OperationOutcome? outcome;

  bool get isRunning => outcome == null;

  /// Сколько объектов задето — по журналу, а не по намерению.
  int get count => journal.length;

  /// Отменима ли: есть что отменять и ничего не мешает.
  bool get canUndo => !isRunning && obstacle == null && journal.isNotEmpty;
}
