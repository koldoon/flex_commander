import 'package:flutter/foundation.dart';

/// Ошибки, которые никто не поймал.
///
/// Приложение не должно молчать о поломках: предусмотреть всё заранее нельзя,
/// и та ошибка, о которой человеку не сказали, выглядит как «просто не
/// сработало». Пойманное сюда показывается окном с подробностями — их можно
/// скопировать и отдать тем, кто чинит.
///
/// Сюда идёт только **непойманное**. Отказы, о которых команда сообщает сама
/// (`FsError` в её окне, вопросы операций), остаются там: одна и та же беда,
/// показанная дважды, выглядит как две разные.
///
/// В API, а не в ядре, потому что докладывать вправе и модуль: он тоже может
/// наткнуться на то, чего не ждал, — и получает службу через
/// `services.resolve<ErrorSink>()`.
abstract interface class Errors implements Listenable {
  /// Ошибка, которую никто не поймал.
  ///
  /// [context] — чем в это время занималось приложение («Packing archive»);
  /// null, если сказать нечего: ошибка отрисовки ни к чему такому не привязана.
  void report(Object error, [StackTrace? stack, String? context]);

  /// Что показывать сейчас; null — показывать нечего.
  ErrorReport? get current;

  /// Сколько ошибок ждёт, считая показанную.
  ///
  /// Одна поломка часто тянет за собой соседние, и по первой судить рано:
  /// счёт видно в заголовке окна.
  int get pending;

  /// Закрыть показанную и перейти к следующей.
  void dismiss();

  /// Положить отчёт о показанной ошибке в буфер обмена.
  ///
  /// Пока это и есть «сообщить»: отправлять некуда, а вставить отчёт в задачу
  /// или письмо можно уже сейчас. false — копировать было нечего.
  Future<bool> copyReport();
}

/// Одна пойманная ошибка — то, что показывают человеку и кладут в отчёт.
///
/// Хранится всё, что удалось вытащить: без стека и типа сообщение «Bad state»
/// не говорит ничего, а по ним ошибку находят в коде за минуту.
class ErrorReport {
  ErrorReport({required this.error, this.stack, this.context, DateTime? time, this.repeats = 1})
    : time = time ?? DateTime.now();

  /// Само исключение — как есть.
  final Object error;

  final StackTrace? stack;

  /// Чем занималось приложение: «Packing archive», имя команды. Может не быть:
  /// ошибка отрисовки ни к чему такому не привязана.
  final String? context;

  final DateTime time;

  /// Сколько раз она повторилась подряд.
  ///
  /// Одна ошибка отрисовки приходит на каждый кадр: без склейки окно
  /// показывало бы сотню одинаковых.
  final int repeats;

  String get type => error.runtimeType.toString();

  String get message => error.toString();

  ErrorReport repeated() => ErrorReport(error: error, stack: stack, context: context, time: time, repeats: repeats + 1);

  /// Две ошибки — об одном и том же.
  ///
  /// По типу, сообщению и верхушке стека: ниже по стеку одна и та же поломка
  /// приходит разными путями, а верх у неё общий.
  bool sameAs(ErrorReport other) => type == other.type && message == other.message && _stackHead == other._stackHead;

  String get _stackHead {
    final lines = stack?.toString().split('\n') ?? const [];
    return lines.take(3).join('\n');
  }

  /// Отчёт для отправки: то, что кладётся в буфер обмена.
  ///
  /// Обычным текстом, а не JSON: его вставляют в задачу или письмо, и читать
  /// его будет человек.
  /// [environment] — строки о машине и сборке: их знает ядро, а не API. Здесь
  /// нет `dart:io` и быть не может (`purity_test`).
  String toReport({Map<String, String> environment = const {}}) {
    final buffer =
        StringBuffer()
          ..writeln('Flex Commander — error report')
          ..writeln('Time: ${time.toIso8601String()}');
    for (final entry in environment.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    if (context != null) {
      buffer.writeln('While: $context');
    }
    if (repeats > 1) {
      buffer.writeln('Repeats: $repeats');
    }
    buffer
      ..writeln()
      ..writeln('$type: $message')
      ..writeln()
      ..writeln(stack?.toString() ?? 'No stack trace');
    return buffer.toString();
  }
}
