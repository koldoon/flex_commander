import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';

import '../link/link.dart';

/// Оболочка, живущая по ту сторону границы.
///
/// Тот же [PtySession], что и настоящий: экран не знает и знать не должен,
/// сидит ли процесс в этом изоляте или в чужом. Отличие одно и оно снаружи не
/// видно — байты сюда приезжают событиями, а клавиши уезжают репликами в
/// разговор (`docs/spec/client-server.md`, §5.1.5).
class RemoteShell implements PtySession {
  RemoteShell(this._link, this.runId) {
    _events = _link.events.listen((event) {
      switch (event) {
        case ShellOutput(runId: final id, :final bytes) when id == runId:
          if (!_output.isClosed) {
            _output.add(Uint8List.fromList(bytes));
          }
        case ShellExited(runId: final id, :final exitCode) when id == runId:
          _finish(exitCode);
        case CoreEvent():
          break;
      }
    });
  }

  final Link _link;

  /// Имя разговора. Дало его ядро: оболочка одна на место.
  final String runId;

  /// Лента широковещательная: смотрят её и разбор вывода, и — случается —
  /// проверка. Одна подписка на всех была бы гонкой за первого слушателя.
  final StreamController<Uint8List> _output = StreamController<Uint8List>.broadcast();
  final Completer<int> _exited = Completer<int>();
  late final StreamSubscription<CoreEvent> _events;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exited.future;

  @override
  void write(Uint8List data) => _link.tell(TellOperation(runId, ShellInput(data)));

  @override
  void resize({required int columns, required int rows}) =>
      _link.tell(TellOperation(runId, ShellResize(columns: columns, rows: rows)));

  @override
  Future<void> kill() async {
    _link.tell(TellOperation(runId, const CancelInput()));
    // Конца не ждём: о нём расскажет событие, а мёртвая оболочка не расскажет
    // ничего — и ждать её было бы вечно.
  }

  void _finish(int code) {
    if (_exited.isCompleted) {
      return;
    }
    _exited.complete(code);
    unawaited(_events.cancel());
    unawaited(_output.close());
  }
}
