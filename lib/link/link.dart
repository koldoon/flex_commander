import 'dart:async';

import 'package:fc_api/fc_api.dart';

/// Что ходит по линку.
///
/// Три рода, и больше не нужно: просьба с именем, ответ на неё по тому же имени
/// и то, что ядро рассказывает само. Имя — число: сообщения ходят по одному
/// каналу, и ответ надо связать с просьбой
/// (`docs/spec/client-server.md`, §5).
sealed class LinkMessage {
  const LinkMessage();
}

final class LinkRequest extends LinkMessage {
  const LinkRequest(this.id, this.request);

  /// Ноль — ответа не ждут: движение курсора, пометка, отмена. Такие просьбы
  /// уходят и не возвращаются, а о последствиях рассказывает событие.
  final int id;
  final CoreRequest request;
}

final class LinkReply extends LinkMessage {
  const LinkReply(this.id, this.reply);

  final int id;
  final CoreReply reply;
}

final class LinkEvent extends LinkMessage {
  const LinkEvent(this.event);

  final CoreEvent event;
}

/// Беда на той стороне: разговор кончился не ответом.
///
/// Отдельным сообщением, а не исключением: исключение через порт не поедет, а
/// текст и стек — поедут. Тип по дороге пропадёт, и притворяться, что он тот
/// же, нельзя: текст — это всё, что скажут человеку
/// (`docs/spec/client-server.md`, §11, урок 4).
final class LinkCrashed extends LinkMessage {
  const LinkCrashed(this.id, this.message, this.trace);

  final int id;
  final String message;
  final String trace;
}

/// Дверь к ядру со стороны интерфейса.
///
/// Реализаций две — петля и порт, — и отличаются они только доставкой.
/// Всё остальное: связывание ответа с просьбой, порядок, смерть той стороны —
/// написано один раз ([CoreLink]).
abstract interface class Link {
  /// Попросить и дождаться ответа.
  Future<CoreReply> call(CoreRequest request);

  /// Сказать и не ждать: курсор, пометка, отмена.
  ///
  /// Порядок с [call] сохраняется — сообщения идут одной чередой, и «поставь
  /// курсор» не обгонит «открой каталог».
  void tell(CoreRequest request);

  /// То, что ядро рассказывает само.
  Stream<CoreEvent> get events;

  Future<void> dispose();
}

/// Та сторона: кто исполняет просьбы.
///
/// Ядро реализует именно это, и ничего не знает ни про линк, ни про то, что
/// та сторона вообще есть.
abstract interface class CoreHandler {
  /// Исполнить просьбу. `null` — отвечать нечего (просьба без ответа).
  Future<CoreReply?> handle(CoreRequest request);

  /// То, что ядро рассказывает само.
  Stream<CoreEvent> get events;
}

/// Клиентская половина линка: имена просьб, ожидание ответов, смерть той
/// стороны.
///
/// Общая для петли и порта — вся разница между ними в том, чем послать
/// сообщение и откуда его получить.
class CoreLink implements Link {
  CoreLink({required void Function(LinkMessage message) send, required Stream<LinkMessage> incoming}) : _send = send {
    _incoming = incoming.listen(_receive, onDone: () => _die('связь с ядром закрыта'));
  }

  final void Function(LinkMessage message) _send;
  late final StreamSubscription<LinkMessage> _incoming;

  final Map<int, Completer<CoreReply>> _waiting = {};
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast();

  int _nextId = 0;
  bool _dead = false;

  @override
  Stream<CoreEvent> get events => _events.stream;

  @override
  Future<CoreReply> call(CoreRequest request) {
    if (_dead) {
      // С мёртвым ядром разговор кончается сразу, а не молчанием: молчаливый
      // пустой ответ оставил бы работу ждать того, чего не будет
      // (`docs/spec/client-server.md`, §11, урок 2).
      return Future.error(StateError('ядро недоступно'));
    }
    final id = ++_nextId;
    final completer = Completer<CoreReply>();
    _waiting[id] = completer;
    _send(LinkRequest(id, request));
    return completer.future;
  }

  @override
  void tell(CoreRequest request) {
    if (_dead) {
      // Сказать мёртвому — тишина, а не ошибка: с ядром ушло и всё, что оно
      // держало (`docs/spec/client-server.md`, §11, урок 8).
      return;
    }
    _send(LinkRequest(0, request));
  }

  void _receive(LinkMessage message) {
    switch (message) {
      case LinkReply(:final id, :final reply):
        _waiting.remove(id)?.complete(reply);
      case LinkEvent(:final event):
        if (!_events.isClosed) {
          _events.add(event);
        }
      case LinkCrashed(:final id, :final message, :final trace):
        _waiting.remove(id)?.completeError(CoreCrashed(message, trace));
      case LinkRequest():
        // Просьбы ходят только в ту сторону.
        break;
    }
  }

  /// Та сторона замолчала: все, кто ждал, получают беду.
  void _die(String reason) {
    if (_dead) {
      return;
    }
    _dead = true;
    for (final completer in _waiting.values.toList()) {
      completer.completeError(CoreCrashed(reason, ''));
    }
    _waiting.clear();
  }

  @override
  Future<void> dispose() async {
    _die('связь с ядром закрыта');
    await _incoming.cancel();
    await _events.close();
  }
}

/// Беда, приехавшая с той стороны.
///
/// Текстом и стеком: тип исключения через границу не поедет, а сказать
/// человеку надо именно текст.
class CoreCrashed implements Exception {
  const CoreCrashed(this.message, this.trace);

  final String message;
  final String trace;

  @override
  String toString() => 'CoreCrashed: $message';
}
