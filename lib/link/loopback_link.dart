import 'dart:async';

import 'package:flutter/foundation.dart';

import 'link.dart';

/// Линк в ту же память: ядро здесь же, но говорят с ним по правилам порта.
///
/// Смысл не в том, чтобы сэкономить изолят, а в том, что **весь прогон идёт
/// через язык границы**. Логика при этом настоящая: петля подменяет только
/// доставку, а не то, что за ней. Это и есть причина, по которой линк вынесен
/// отдельно, а не спрятан внутрь изолята (`docs/spec/client-server.md`, §10).
///
/// **Доставка прямым вызовом**, и это решение, а не упрощение. Поток помнит тот
/// поток исполнения, в котором на него подписались, и зовёт обработчик там же —
/// а приложение в прогоне собирают до начала теста, вне его поддельного
/// времени. Работа тогда шла бы не когда прогон крутит кадры, а когда ему
/// случится подождать по-настоящему: проверки становятся шаткими, а причина —
/// невидимой. Прямой вызов исполняет просьбу там же, откуда её сказали, и
/// порядок остаётся тем же, каким его увидит порт: событие уходит раньше
/// ответа, потому что случается раньше.
class LoopbackLink extends CoreLink {
  LoopbackLink(this._core) {
    _unlisten = _core.listen((event) => receive(LinkEvent(event)));
  }

  final CoreHandler _core;
  late final VoidCallback _unlisten;

  @override
  void send(LinkMessage message) {
    if (message is! LinkRequest) {
      return;
    }
    unawaited(
      _core
          .handle(message.request)
          .then((reply) {
            if (reply != null && message.id != 0) {
              receive(LinkReply(message.id, reply));
            }
          })
          .catchError((Object error, StackTrace stack) {
            // Беда переносится текстом и исходным стеком: иначе искать причину
            // станет вдвое дороже.
            receive(LinkCrashed(message.id, error.toString(), stack.toString()));
          }),
    );
  }

  @override
  Future<void> dispose() async {
    _unlisten();
    await super.dispose();
  }
}
