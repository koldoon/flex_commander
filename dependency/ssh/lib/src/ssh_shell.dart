import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Оболочка на той стороне — [PtySession] поверх канала `dartssh2`.
///
/// Перевод живёт здесь, а не в провайдере, по той же причине, что и разбор
/// SFTP: провайдер не должен зависеть от библиотеки. Ложится он почти
/// дословно — `stdout` и `stderr` в один поток, `stdin` в запись, изменение
/// размера в изменение размера.
class SshPtySession implements PtySession {
  SshPtySession(this._session) : _output = mergedOutput(_session.stdout, _session.stderr);

  final SSHSession _session;
  final Stream<Uint8List> _output;

  @override
  Stream<Uint8List> get output => _output;

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

/// Вывод и ошибки — одним потоком.
///
/// В псевдотерминале это и есть один поток: программа пишет и то и другое в
/// один и тот же терминал, и порядок между ними — тот, в каком она их
/// выводила. Разделены они здесь только устройством библиотеки, и разбирать их
/// порознь значило бы перемешать сообщения об ошибках с выводом не в том
/// порядке, в каком они появились.
///
/// **Слушаем оба, а не `addStream`.** Двух одновременных `addStream` у одного
/// контроллера не бывает: второй падает «Cannot add event while adding a
/// stream». Поймано живьём, на первом же `Ctrl-O` по ssh.
Stream<Uint8List> mergedOutput(Stream<Uint8List> stdout, Stream<Uint8List> stderr) {
  final merged = StreamController<Uint8List>();
  var open = 2;

  void done() {
    if (--open <= 0 && !merged.isClosed) {
      unawaited(merged.close());
    }
  }

  // Ошибка канала — это конец потока, а не событие для терминала: показать её
  // всё равно нечем, а код возврата скажет о случившемся точнее.
  final subscriptions = [
    stdout.listen(merged.add, onDone: done, onError: (Object _) => done(), cancelOnError: true),
    stderr.listen(merged.add, onDone: done, onError: (Object _) => done(), cancelOnError: true),
  ];

  merged.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };

  return merged.stream;
}
