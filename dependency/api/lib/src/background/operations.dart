import 'package:flutter/foundation.dart';

import '../app/viewport.dart';
import '../async/async_operation.dart';
import '../async/operation_status.dart';

/// Заведённая работа: сама она и то, что про неё знает реестр.
class OperationRun {
  OperationRun({required this.runId, required this.operation, required this.title, this.bringToFront});

  final String runId;

  final Operation<Object?, Object?> operation;

  /// Что показать в полоске: «Copy 3 items».
  ///
  /// Хранится, а не берётся у команды: имя команды — это «Copy», а сколько
  /// объектов в работе, знал только тот, кто её заводил.
  final String title;

  /// Под какой панелью показывать полоску; null — работа не в фоне.
  ///
  /// Заведённая работа в статусной области **не** появляется: она идёт со
  /// своим окном. Полоска возникает только после [Operations.sendToBackground],
  /// и область называют там же — где показывать, имеет смысл только когда
  /// показывают.
  ///
  /// Привязка к позиции, а не к объекту панели: панель заменяема, позиция нет.
  ViewportPosition? owner;

  /// Чем показать эту работу снова; null — показывать нечем.
  ///
  /// Реестру незачем знать, **как** это делается, и незачем знать команду: окно
  /// строит тот, кто работу завёл, — он и оставляет здесь, чем его вернуть.
  /// Иначе реестру пришлось бы разбираться в командах, окнах и их состояниях, а
  /// команде — собирать состояние заново поверх уже идущей работы.
  final VoidCallback? bringToFront;

  bool get isInBackground => owner != null;

  OperationStatus get status => operation.status;
}

/// Заведённые работы.
abstract interface class Operations implements Listenable {
  /// Все работы, о которых реестр знает.
  List<OperationRun> get all;

  /// Работы, которые показывает статусная область под этой панелью, — только
  /// ушедшие в фон.
  List<OperationRun> at(ViewportPosition position);

  OperationRun? byId(String runId);

  /// Заводит работу: с этого момента её можно найти — собрать окно заново,
  /// поднять заявку, дождаться.
  ///
  /// В статусной области её после этого нет: для этого есть [sendToBackground].
  /// Работа, которую и находить незачем — чтение файла для быстрого просмотра,
  /// определение типа по содержимому, — не заводится вовсе.
  ///
  /// Идентификатор приходит снаружи, а не минтится здесь: пока работу заводит
  /// команда, он у неё уже есть. Станет `start`, минтящим свой, когда работа
  /// научится создаваться отдельно от запуска — см. долг про `execute(P)`.
  void register(OperationRun run);

  /// Убирает окно и оставляет работу идти: полоска появляется в статусной
  /// области под названной панелью.
  ///
  /// Отдельное действие, а не следствие закрытия окна: работа, идущая молча и
  /// невидимо, — худшее из состояний.
  void sendToBackground(String runId, {required ViewportPosition owner});

  /// Возвращает окно работы, ушедшей в фон.
  void bringToFront(String runId);

  /// Убирает работу из списка: её полоска отжила своё.
  void forget(String runId);
}
