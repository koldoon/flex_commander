import 'dart:async';
import 'dart:io';

import 'package:fc_api/fc_api.dart';

/// Приёмник, который пишет во временный файл, а на месте цели оказывается
/// через `sudo`.
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
    required File temporary,
    required this.about,
  }) : _temporary = temporary,
       _sink = temporary.openWrite() {
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

  final File _temporary;
  final IOSink _sink;
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
      final moved = await elevation.copyOver(host: host, temporary: _temporary.path, target: target, about: about);
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
        if (await _temporary.exists()) {
          await _temporary.delete();
        }
      } on FileSystemException {
        // Не убрался — не беда, за него отвечает система уборки временных.
      }
    }
  }
}
