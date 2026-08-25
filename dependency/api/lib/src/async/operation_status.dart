import 'package:flutter/foundation.dart';

import 'operation_request.dart';

/// Ход длительной работы.
///
/// Объект, а не поток событий: тот, кто рисует, подписывается обычным
/// `ListenableBuilder` и читает то, что есть **сейчас**. Поздний подписчик
/// ничего не пропускает — ему не нужно переигрывать последнее событие,
/// потому что состояние никуда не девалось.
///
/// Этого хватает универсальному месту — компактной полоске в статусной
/// области: по [state] она понимает, показывать ли кнопку «нужен ответ», и
/// дальше не заглядывает. Окно работы строит команда, знает её тип и приводит
/// к нужному подтипу один раз.
abstract interface class OperationStatus implements Listenable {
  OperationState get state;

  /// Что происходит прямо сейчас — короткой строкой.
  String get message;

  // Троттлинг перерисовки — обязанность реализации, а не того, кто рисует:
  // копирование отчитывается на каждый блок, и уведомлять на каждый отчёт
  // значит положить окно.
}

/// Состояние работы.
enum OperationState {
  inited,
  pending,
  processing,

  /// Работа встала и ждёт человека. Ждёт столько, сколько нужно.
  userActionRequired,
  complete,
  canceled,
  error;

  bool get isFinished => this == complete || this == canceled || this == error;
}

/// Подтип говорит про **род** работы, null внутри — про «пока неизвестно».
///
/// «Есть ли скорость» — факт времени выполнения: первые полсекунды считать не
/// из чего. Копирование измеримо *по природе*, поэтому тип правильный всегда,
/// а значение nullable — иначе пришлось бы вернуть 0, то есть соврать.
abstract interface class ComputableOperationStatus extends OperationStatus {
  /// 0…1; null — прогресс неопределённый.
  double? get percentProgress;
}

abstract interface class MeasurableOperationStatus extends OperationStatus {
  /// Байт в секунду; null — считать пока не из чего.
  double? get speed;

  /// Сколько ещё ждать; null — оценить не из чего.
  Duration? get remaining;
}

/// Ход по одному объекту.
abstract interface class SingleTransferOperationStatus extends ComputableOperationStatus {
  /// Объект, который обрабатывается сейчас; пусто — работа не разбита на
  /// объекты.
  String get itemName;

  int get bytesTransferred;

  /// null — размер не известен и известен не будет.
  int? get bytesTotal;
}

/// Ход по множеству объектов.
abstract interface class MultipleTransferOperationStatus extends ComputableOperationStatus {
  int get itemsTransferred;

  /// null — ещё считается фоном: обход большого дерева сам по себе долгий.
  int? get itemsTotal;

  /// Досчитано ли [itemsTotal]. Пока нет — это нижняя оценка.
  bool get totalIsFinal;
}

/// Этап многоэтапной работы.
abstract interface class StageOperationStatus {
  String get name;
}

/// Работа из нескольких этапов с отдельным ходом у каждого.
///
/// Список может **расти по ходу**: второй этап («перепаковка архива»)
/// появляется, только если в деле оказался пакетный приёмник.
abstract interface class MultistageOperationStatus extends OperationStatus {
  List<StageOperationStatus> get stages;
}

/// Работа, которую можно приостановить вопросом.
abstract interface class InteractiveOperationStatus extends OperationStatus {
  /// null — вопроса сейчас нет.
  ///
  /// Что вопрос есть, универсальное место узнаёт по
  /// [OperationState.userActionRequired], сюда не заглядывая.
  UserActionRequest? get request;
}
