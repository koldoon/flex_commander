import 'dart:async';

import 'package:fc_api/fc_api.dart';

import '../link/link.dart';

/// Содержимое файла, лежащего за границей.
///
/// Разговор открывается на `read()`, а не заранее: показ решает сам, читать ли
/// ему и с какого места, — а лишний поход за байтами стоит ровно того файла,
/// который никто не собирался открывать.
class RemoteContent implements Content {
  RemoteContent(this._link, this._entry, {required this.length});

  final Link _link;
  final EntryRef _entry;

  @override
  final int length;

  static var _nextRead = 0;

  @override
  Stream<List<int>> read({int offset = 0}) {
    final runId = 'read#${_nextRead++}';
    final out = StreamController<List<int>>();
    late final StreamSubscription<CoreEvent> events;

    events = _link.events.listen((event) {
      switch (event) {
        case ContentChunk(runId: final id, :final bytes) when id == runId:
          if (!out.isClosed) {
            out.add(bytes);
          }
        case ContentEnded(runId: final id, :final error, :final message) when id == runId:
          if (!out.isClosed) {
            if (error != null) {
              out.addError(error);
            } else if (message.isNotEmpty) {
              out.addError(Exception(message));
            }
            unawaited(out.close());
          }
          unawaited(events.cancel());
        case CoreEvent():
          break;
      }
    });

    // Читать перестают, закрыв поток: показ закрыли, курсор ушёл дальше — и
    // тянуть байты с сервера больше незачем.
    out.onCancel = () {
      _link.tell(TellOperation(runId, const CancelInput()));
      return events.cancel();
    };

    // Подписка встала — можно просить: первый же кусок не пройдёт мимо.
    _link.tell(ReadContent(runId, _entry, offset: offset));
    return out.stream;
  }
}
