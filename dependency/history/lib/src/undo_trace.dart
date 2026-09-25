import 'package:flutter/foundation.dart';

/// Щуп за отменой: какие записи пришли и что с каждой стало.
///
/// Включается сборкой — `--dart-define=FC_UNDO_TRACE=1`, — и без неё не стоит
/// ничего: константа из окружения, ветка выбрасывается компилятором. Строкой, а
/// не `bool.fromEnvironment`: тот считает истиной только слово `true`, и `=1`
/// молча выключал бы щуп (урок щупа за деревом).
const bool undoTraceOn = String.fromEnvironment('FC_UNDO_TRACE') != '';

void traceUndo(String what) {
  if (!undoTraceOn) {
    return;
  }
  final now = DateTime.now();
  final at =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('ОТМЕНА $at $what');
}
