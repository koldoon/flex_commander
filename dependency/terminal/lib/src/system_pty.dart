import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_pty/flutter_pty.dart';

/// Настоящий псевдотерминал системы.
///
/// Единственное место модуля, знающее про `flutter_pty`. Всё остальное написано
/// против [PtyLauncher] — и потому проверяется на подставке, без оболочки на
/// машине, где идёт прогон.
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
      Pty.start(
        executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment.isEmpty ? null : environment,
        columns: columns,
        rows: rows,
      ),
    );
  }
}

class _SystemPtySession implements PtySession {
  _SystemPtySession(this._pty);

  final Pty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;

  @override
  void write(Uint8List data) => _pty.write(data);

  /// Порядок аргументов у `flutter_pty` обратный привычному: сначала строки.
  @override
  void resize({required int columns, required int rows}) => _pty.resize(rows, columns);

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  Future<void> kill() async => _pty.kill();
}
