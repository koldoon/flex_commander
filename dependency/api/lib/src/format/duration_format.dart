/// Оставшееся время для окна операции: `00:42`, `07:15`, `1:23:45`.
///
/// Часы печатаются только когда они есть: «00:07:15» на семь минут выглядит
/// как ошибка. Отрицательное и неизвестное сюда не попадает — этим занимается
/// тот, кто решает, показывать ли оценку вообще.
String formatDuration(Duration value) {
  final seconds = value.inSeconds;
  final minutes = seconds ~/ 60;
  final hours = minutes ~/ 60;

  final mm = (minutes % 60).toString().padLeft(2, '0');
  final ss = (seconds % 60).toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
