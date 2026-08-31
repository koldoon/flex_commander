import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fc_api/fc_api.dart';

/// Оболочка на той стороне — [PtySession] поверх канала `dartssh2`.
///
/// Перевод живёт здесь, а не в провайдере, по той же причине, что и разбор
/// SFTP: провайдер не должен зависеть от библиотеки. Ложится он почти
/// дословно — `stdout` и `stderr` в один поток, `stdin` в запись, изменение
/// размера в изменение размера.
class SshPtySession implements PtySession {
  SshPtySession(this._session) {
    // Оба потока в один: в псевдотерминале они и так один, а разделены здесь
    // только устройством библиотеки. Разбирать их порознь значило бы
    // перемешать вывод программы с её же сообщениями об ошибках не в том
    // порядке, в каком они появились.
    _output
      ..addStream(_session.stdout).whenComplete(_closeWhenDone)
      ..addStream(_session.stderr).whenComplete(_closeWhenDone);
  }

  final SSHSession _session;
  final StreamController<Uint8List> _output = StreamController<Uint8List>();
  int _openStreams = 2;

  void _closeWhenDone() {
    if (--_openStreams <= 0 && !_output.isClosed) {
      unawaited(_output.close());
    }
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) => _session.stdin.add(data);

  @override
  void resize({required int columns, required int rows}) => _session.resizeTerminal(columns, rows);

  /// Код возврата; сервер вправе его не прислать — тогда −1, как у оборванной
  /// программы на своей машине.
  @override
  Future<int> get exitCode async => await _session.waitForExit() ?? -1;

  @override
  Future<void> kill() async {
    // Сигнал, а не закрытие канала: закрытый канал оставил бы на сервере
    // работающую программу без ввода, а `htop` так не остановить.
    _session.kill(SSHSignal.TERM);
    _session.close();
  }
}
