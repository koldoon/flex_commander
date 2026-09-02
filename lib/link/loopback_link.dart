import 'dart:async';

import 'link.dart';

/// Линк в ту же память: ядро здесь же, но говорят с ним по правилам порта.
///
/// Смысл не в том, чтобы сэкономить изолят, а в том, что **весь прогон идёт
/// через язык границы**. Логика при этом настоящая: петля подменяет только
/// доставку, а не то, что за ней. Это и есть причина, по которой линк вынесен
/// отдельно, а не спрятан внутрь изолята (`docs/spec/client-server.md`, §10).
///
/// **Доставка синхронная**, и это решение, а не упрощение. Асинхронная петля
/// заводит собственную очередь микрозадач, и та живёт в том потоке, где
/// **создан** контроллер, — а приложение в прогоне собирают до начала теста,
/// вне его поддельного времени. Работа тогда идёт не тогда, когда прогон
/// крутит кадры, а когда ему случится подождать по-настоящему: проверки
/// становятся шаткими, а причина — невидимой. Синхронная петля исполняет
/// просьбу там же, откуда её сказали, и порядок остаётся тем же, каким его
/// увидит порт: событие уходит раньше ответа, потому что случается раньше.
class LoopbackLink extends CoreLink {
  LoopbackLink._(CoreHandler core, this._incoming, this._events)
    : super(send: _dispatch(core, _incoming), incoming: _incoming.stream);

  factory LoopbackLink(CoreHandler core) {
    // Синхронный: `add` доставляет сообщение сразу, в том же потоке, где его
    // сказали, — без собственной очереди и без чужого потока.
    final incoming = StreamController<LinkMessage>.broadcast(sync: true);
    final events = core.events.listen((event) {
      if (!incoming.isClosed) {
        incoming.add(LinkEvent(event));
      }
    });
    return LoopbackLink._(core, incoming, events);
  }

  final StreamController<LinkMessage> _incoming;
  final StreamSubscription<Object?> _events;

  /// Просьба уходит прямо в ядро; ответ возвращается по тому же имени.
  ///
  /// Событий, случившихся по ходу исполнения, это не обгоняет: они уходят
  /// синхронно, изнутри самого исполнения, а ответ добавляется после его
  /// конца.
  static void Function(LinkMessage message) _dispatch(CoreHandler core, StreamController<LinkMessage> incoming) {
    return (message) {
      if (message is! LinkRequest) {
        return;
      }
      unawaited(
        core
            .handle(message.request)
            .then((reply) {
              if (reply != null && message.id != 0 && !incoming.isClosed) {
                incoming.add(LinkReply(message.id, reply));
              }
            })
            .catchError((Object error, StackTrace stack) {
              // Беда переносится текстом и исходным стеком: иначе искать
              // причину станет вдвое дороже.
              if (!incoming.isClosed) {
                incoming.add(LinkCrashed(message.id, error.toString(), stack.toString()));
              }
            }),
      );
    };
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _events.cancel();
    await _incoming.close();
  }
}
