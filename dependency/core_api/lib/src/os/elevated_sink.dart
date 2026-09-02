import 'dart:async';

import 'package:fc_api/fc_api.dart';

import 'elevation.dart';
import 'pty.dart';

/// Приёмник, который пишет во временный файл, а на месте цели оказывается
/// через `sudo`.
///
/// Общий для обеих сторон: чем открыть временный файл и чем его убрать, знает
/// провайдер — у диска это `dart:io`, у сервера SFTP, — а всё остальное у них
/// одинаково. Тонкие места (отказ как `FsError`, уборка в любом исходе, второй
/// канал `done`) стоят дорого, и держать их в двух копиях верный способ
/// разойтись.
///
/// Заводится там, где обычная запись отказала бы по правам, и только когда
/// повышение разрешено. Снаружи он неотличим от обычного приёмника: тот, кто
/// пишет — редактор, движок переноса, — про повышение не знает ничего.
///
/// **Временный файл, а не память.** Копировать в системный каталог можно и
/// образ на четыре гигабайта; держать его в памяти ради одного `cp` нельзя.
class ElevatedSink implements StreamSink<List<int>> {
  ElevatedSink({
    required this.elevation,
    required this.host,
    required this.target,
    required this.temporary,
    required this.about,
    required StreamSink<List<int>> into,
    required Future<void> Function() removeTemporary,
  }) : _sink = into,
       _remove = removeTemporary {
    // Неудача приходит вызывающему из `close()`; `done` — второй, необязательный
    // канал той же новости. Без этого отказ, на который никто не подписался,
    // всплывал бы необработанным и ронял приложение мимо всех обработчиков.
    _done.future.ignore();
  }

  final Elevation elevation;

  /// Где выполнять `sudo`: та же сторона, где лежит цель.
  final ShellHost host;

  /// Куда в итоге положить — полным путём.
  final String target;

  final ElevationRequest about;

  /// Куда пишем, пока не дошло до `sudo`, — путь **на той же стороне**, что и
  /// цель: `cp` выполняется там, и путь ему нужен тамошний.
  final String temporary;

  final StreamSink<List<int>> _sink;

  /// Как убрать временный: у диска и у сервера это разные действия.
  final Future<void> Function() _remove;
  final Completer<void> _done = Completer<void>();

  @override
  void add(List<int> data) => _sink.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _sink.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    try {
      await _sink.close();
      final moved = await elevation.copyOver(host: host, temporary: temporary, target: target, about: about);
      if (!moved) {
        // Отказались — значит отказ и есть: тот же, что был бы без повышения.
        throw FsError(target, FsErrorKind.permissionDenied);
      }
      if (!_done.isCompleted) {
        _done.complete();
      }
    } on Object catch (error, stack) {
      if (!_done.isCompleted) {
        _done.completeError(error, stack);
      }
      rethrow;
    } finally {
      // Временного за собой не оставляем ни в каком исходе: он лежит в общем
      // каталоге и содержит то, что человек только что писал.
      try {
        await _remove();
      } on Object {
        // Не убрался — не беда: за общий каталог отвечает система уборки
        // временных, а ронять из-за этого запись, которая уже прошла, нельзя.
      }
    }
  }
}
