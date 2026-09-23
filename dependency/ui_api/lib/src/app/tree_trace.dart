import 'package:flutter/foundation.dart';

/// Щуп за комбинированным видом: что нарисовано в дереве, где курсор, что
/// показывает список и какие клавиши нажимали.
///
/// Включается сборкой — `--dart-define=FC_TREE_TRACE=1`, — и без неё не стоит
/// ничего: константа из окружения, ветка выбрасывается компилятором.
///
/// Время — **стенные часы**: у каждого изолята свой отсчёт, и сравнивать
/// секундомеры двух сторон бессмысленно (живой разбор 22 сентября 2026).
/// Строкой, а не `bool.fromEnvironment`: тот считает истиной **только** слово
/// `true`, и `FC_TREE_TRACE=1` молча выключает щуп — на этом уже потерян один
/// прогон (23 сентября 2026).
const bool treeTraceOn = String.fromEnvironment('FC_TREE_TRACE') != '';

void traceTree(String who, String what) {
  if (!treeTraceOn) {
    return;
  }
  final now = DateTime.now();
  final at =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('ЩУП $at ${who.padRight(8)} $what');
}
