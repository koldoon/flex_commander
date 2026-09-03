import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'posix_pty.dart';

/// Настоящий псевдотерминал системы.
///
/// Единственное место модуля, знающее, как он устроен. Всё остальное написано
/// против [PtyLauncher] — и потому проверяется на подставке.
class SystemPtyLauncher implements PtyLauncher {
  const SystemPtyLauncher();

  @override
  PtySession start({
    required String executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String> environment = const {},
    int columns = 80,
    int rows = 24,
  }) {
    return _SystemPtySession(
      PosixPty.start(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        columns: columns,
        rows: rows,
      ),
    );
  }
}

/// Запущенная программа: чтение в своём изоляте, всё остальное — прямыми
/// вызовами.
class _SystemPtySession implements PtySession {
  _SystemPtySession(this._pty) {
    _messages.listen(_onMessage);
    _reader = Isolate.spawn(PtyReader.run, (_pty.master, _pty.pid, _messages.sendPort), debugName: 'pty:${_pty.pid}');
  }

  final PosixPty _pty;

  /// Изолят чтения: его надо чем-то остановить, когда программа кончилась.
  ///
  /// Сам он выйдет и так — но не мгновенно: последним делом он ждёт кода
  /// возврата. Оставлять висеть незачем, а без ссылки его и не остановить.
  late final Future<Isolate> _reader;
  final ReceivePort _messages = ReceivePort();
  final StreamController<Uint8List> _output = StreamController<Uint8List>.broadcast();
  final Completer<int> _exit = Completer<int>();

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(Uint8List data) => _pty.write(data);

  @override
  void resize({required int columns, required int rows}) => _pty.resize(columns: columns, rows: rows);

  @override
  Future<void> kill() async {
    if (_exit.isCompleted) {
      return;
    }
    _pty.terminate();
    // Ждём не вечно: программа, которая не уходит по `SIGTERM`, не должна
    // задерживать выход приложения.
    await _exit.future.timeout(const Duration(seconds: 2), onTimeout: () => -1);
  }

  /// Изолят чтения шлёт байты, а последним сообщением — код возврата.
  void _onMessage(dynamic message) {
    if (message is Uint8List) {
      _output.add(message);
      return;
    }
    if (message is int) {
      _finish(message);
    }
  }

  void _finish(int code) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
    _messages.close();
    _pty.closeMaster();
    unawaited(_output.close());
    unawaited(_reader.then((isolate) => isolate.kill(priority: Isolate.immediate)));
  }
}
