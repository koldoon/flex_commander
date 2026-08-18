import 'package:flutter/foundation.dart';

/// Ход длительной работы — то, что ядро показывает вне окна команды.
///
/// Окно команды рисует она сама, а вот когда работа ушла в фон, показывать её
/// приходится общим местом: там нет ни полей ввода, ни вопросов — только
/// название, ход дела и возможность прервать.
abstract interface class TaskStatus implements Listenable {
  /// Заголовок для общего списка: «Copy 3 items».
  String get title;

  /// Что происходит прямо сейчас — короткой строкой.
  String get message;

  /// Доля выполненного, 0…1; null — прогресс неопределённый.
  double? get progress;

  bool get isRunning;

  /// Есть ли чем прервать работу.
  bool get canCancel;

  void cancel();

  /// Завершение работы: успешное, с ошибкой или отменённое.
  Future<void> get completion;
}

/// Работы, ушедшие в фон.
///
/// Окно команды принадлежит команде, но решение, показывать его или нет, —
/// ядру: длительную работу можно убрать с глаз и оставить идти, а следить за
/// ней в общем месте вместе с остальными такими же.
abstract interface class BackgroundTasks implements Listenable {
  /// Работы, у которых сейчас нет своего окна.
  List<TaskStatus> get tasks;

  /// Убирает окно команды, оставляя работу идти.
  void sendToBackground(String runId);

  /// Показывает окно снова — например, потому что операция задала вопрос.
  void bringToFront(String runId);

  bool isInBackground(String runId);
}
