import 'dart:async';
import 'dart:isolate';

import 'link.dart';

/// Дверь к ядру, живущему в **другом изоляте**.
///
/// Вся разница с петлёй — доставка: сообщение уходит в порт и приходит из
/// порта. Имена просьб, ожидание ответов и смерть той стороны написаны один раз
/// в [CoreLink] и здесь не повторяются
/// (`docs/spec/client-server.md`, §10).
///
/// Смерть ядра обязана кончать бедой **и идущие разговоры, и новые**: молчаливый
/// пустой ответ оставил бы работу ждать вечно
/// (`docs/spec/client-server.md`, §11, урок 2). Поэтому слушаются оба порта —
/// и `onExit`, и `onError`: изолят уходит и тем и другим путём.
class IsolateLink extends CoreLink {
  IsolateLink._(this._isolate, this._toCore, this._fromCore, this._exit, this._errors) {
    _incoming = _fromCore.listen((message) {
      if (message is LinkMessage) {
        receive(message);
      }
    });
    _exited = _exit.listen((_) => _crash('ядро остановилось'));
    _failed = _errors.listen((error) => _crash('ядро упало: $error'));
  }

  /// Поднимает ядро в своём изоляте и открывает к нему дверь.
  ///
  /// [entry] — точка входа: она получает [payload] и поднимает всё остальное
  /// сама. Кода отсюда туда не уезжает — только порт и то немногое, без чего
  /// изолят не начнёт: ядро он собирает **у себя**, по тем же спискам модулей.
  static Future<IsolateLink> spawn<T>(void Function(T message) entry, T Function(SendPort back) payload) async {
    final fromCore = ReceivePort();
    final exit = ReceivePort();
    final errors = ReceivePort();

    // Первое, что приезжает по этому порту, — порт ядра. Ждём именно его: до
    // рукопожатия дверь закрыта.
    final incoming = fromCore.asBroadcastStream();
    final handshake = incoming.first;

    final isolate = await Isolate.spawn(
      entry,
      payload(fromCore.sendPort),
      onExit: exit.sendPort,
      onError: errors.sendPort,
      errorsAreFatal: true,
      debugName: 'flex-commander-core',
    );

    final toCore = await handshake as SendPort;
    return IsolateLink._(isolate, toCore, incoming, exit, errors);
  }

  final Isolate _isolate;
  final SendPort _toCore;
  final Stream<dynamic> _fromCore;
  final ReceivePort _exit;
  final ReceivePort _errors;

  late final StreamSubscription<dynamic> _incoming;
  late final StreamSubscription<dynamic> _exited;
  late final StreamSubscription<dynamic> _failed;

  bool _closed = false;

  @override
  void send(LinkMessage message) {
    if (_closed) {
      return;
    }
    _toCore.send(message);
  }

  void _crash(String reason) {
    if (_closed) {
      // Уходим сами: это не беда, а конец разговора.
      return;
    }
    dieWith(reason);
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    await _incoming.cancel();
    await _exited.cancel();
    await _failed.cancel();
    _exit.close();
    _errors.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    await super.dispose();
  }
}
