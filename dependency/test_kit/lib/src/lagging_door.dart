import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/link/link.dart';

/// Дверь, придерживающая подтверждения ядра.
///
/// На петле ядро отвечает в том же кадре, и такого не бывает; на порту —
/// бывает всегда: этой стороне помечено уже пятнадцать объектов, а
/// подтверждение идёт про первый (`docs/spec/client-server.md`, §5.5).
/// Задержка поддельная, как и время в прогоне: кадр её и двигает.
///
/// Живёт в наборе для проверок, а не в одном из них: гонки на границе ловятся
/// этим приёмом в нескольких местах сразу — пометка в дереве, столбцы
/// комбинированного вида.
class LaggingDoor implements Link {
  LaggingDoor(this._link);

  static const Duration delay = Duration(milliseconds: 100);

  final Link _link;
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast();
  StreamSubscription<CoreEvent>? _listening;

  @override
  Stream<CoreEvent> get events {
    _listening ??= _link.events.listen((event) {
      Future<void>.delayed(delay, () {
        if (!_events.isClosed) {
          _events.add(event);
        }
      });
    });
    return _events.stream;
  }

  @override
  Future<CoreReply> call(CoreRequest request) => _link.call(request);

  @override
  void tell(CoreRequest request) => _link.tell(request);

  @override
  bool get isOpen => _link.isOpen;

  @override
  Future<void> dispose() async {
    await _listening?.cancel();
    await _events.close();
    await _link.dispose();
  }
}
