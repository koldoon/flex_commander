import 'dart:async';

import 'link.dart';

/// Линк в ту же память: ядро здесь же, но говорят с ним по правилам порта.
///
/// Смысл не в том, чтобы сэкономить изолят, а в том, что **весь прогон идёт
/// через язык границы**. Логика при этом настоящая: петля подменяет только
/// доставку, а не то, что за ней. Это и есть причина, по которой линк вынесен
/// отдельно, а не спрятан внутрь изолята
/// (`docs/spec/client-server.md`, §10).
///
/// Доставка **асинхронная**, и это тоже не мелочь: через порт сообщение всегда
/// приходит следующим оборотом очереди, и петля обязана вести себя так же —
/// иначе порядок, сложившийся на прямых вызовах, развалится на изоляте.
class LoopbackLink extends CoreLink {
  LoopbackLink._(this._toCore, this._fromCore, this._subscriptions)
    : super(send: _toCore.add, incoming: _fromCore.stream);

  factory LoopbackLink(CoreHandler core) {
    final toCore = StreamController<LinkMessage>();
    final fromCore = StreamController<LinkMessage>();
    final subscriptions = <StreamSubscription<Object?>>[];

    // Та сторона слушает просьбы и отвечает по тому же имени. Очередь одна,
    // поэтому порядок сохраняется: «поставь курсор» не обгонит «открой
    // каталог», даже если первое не ждёт ответа.
    subscriptions.add(
      toCore.stream
          .asyncMap((message) async {
            if (message is! LinkRequest) {
              return;
            }
            try {
              final reply = await core.handle(message.request);
              if (reply != null && message.id != 0 && !fromCore.isClosed) {
                fromCore.add(LinkReply(message.id, reply));
              }
            } on Object catch (error, stack) {
              // Беда переносится текстом и исходным стеком: иначе искать причину
              // станет вдвое дороже (`docs/spec/client-server.md`, §11, урок 4).
              if (!fromCore.isClosed) {
                fromCore.add(LinkCrashed(message.id, error.toString(), stack.toString()));
              }
            }
          })
          .listen(null),
    );

    subscriptions.add(
      core.events.listen((event) {
        if (!fromCore.isClosed) {
          fromCore.add(LinkEvent(event));
        }
      }),
    );

    return LoopbackLink._(toCore, fromCore, subscriptions);
  }

  final StreamController<LinkMessage> _toCore;
  final StreamController<LinkMessage> _fromCore;
  final List<StreamSubscription<Object?>> _subscriptions;

  @override
  Future<void> dispose() async {
    await super.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _toCore.close();
    await _fromCore.close();
  }
}
