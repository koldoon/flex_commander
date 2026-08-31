import 'package:flutter_test/flutter_test.dart';

/// Дождаться, пока случится ожидаемое.
///
/// Обороты очереди **и** настоящее время. Разница существенная: `pumpEventQueue`
/// прокручивает очередь, но не двигает часы, а работа, которую ждут, часто идёт
/// на диск — уборка временного файла, запись, переименование. Сколько очередь
/// ни крути, файл удаляется столько, сколько удаляется.
///
/// Отсюда и шаткость, которую это лечит: на быстрой машине оборотов хватало, на
/// сборочной — нет, и тест падал через раз. Поймано дважды: на уборке временной
/// копии архива и на сохранении в редакторе.
///
/// Ждёт **до** исхода, а не заданное время: успело раньше — вернётся сразу, и
/// прогон не удлиняется.
Future<void> waitUntil(bool Function() done, {int tries = 200, Duration step = const Duration(milliseconds: 2)}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await pumpEventQueue(times: 1);
    if (!done()) {
      await Future<void>.delayed(step);
    }
  }
}

/// То же, но условие асинхронное: существование файла спрашивают у системы.
Future<void> waitUntilAsync(
  Future<bool> Function() done, {
  int tries = 200,
  Duration step = const Duration(milliseconds: 2),
}) async {
  for (var i = 0; i < tries; i++) {
    if (await done()) {
      return;
    }
    await pumpEventQueue(times: 1);
    await Future<void>.delayed(step);
  }
}
