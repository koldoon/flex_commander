import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_core_api/fc_core_api.dart';

/// Псевдотерминал, которого нет: запуск записывается, а вывод пишет тест.
///
/// Настоящей оболочки прогон трогать не должен — она переживёт его самого,
/// если что-то пойдёт не так, а на сборочной машине её может не быть вовсе.
class FakePty implements PtyLauncher {
  /// Все запуски по порядку. Их должно быть немного: сессия одна на
  /// приложение, и второй запуск — уже повод посмотреть, откуда он взялся.
  final List<FakePtySession> sessions = [];

  /// Единственная сессия; бросает, если её нет или их несколько.
  FakePtySession get session => sessions.single;

  /// Сессия уже заведена — то есть оболочку успели запустить.
  bool get started => sessions.isNotEmpty;

  @override
  PtySession start({
    required String executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String> environment = const {},
    int columns = 80,
    int rows = 24,
  }) {
    final session = FakePtySession(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      columns: columns,
      rows: rows,
    );
    sessions.add(session);
    return session;
  }
}

/// Запущенная подставка: помнит, что ей отправили, и говорит то, что велят.
class FakePtySession implements PtySession {
  FakePtySession({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.columns,
    required this.rows,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;

  int columns;
  int rows;
  bool killed = false;

  /// Всё, что отправили программе, — строками: тесту важно не то, какими
  /// байтами это поехало, а что именно.
  final List<String> writes = [];

  /// Отправленное одной строкой.
  String get written => writes.join();

  final StreamController<Uint8List> _output = StreamController<Uint8List>.broadcast();
  final Completer<int> _exit = Completer<int>();

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  void write(Uint8List data) => writes.add(utf8.decode(data, allowMalformed: true));

  @override
  void resize({required int columns, required int rows}) {
    this.columns = columns;
    this.rows = rows;
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> kill() async {
    killed = true;
    _finish(-1);
  }

  /// Программа что-то вывела.
  void emit(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  /// Программа завершилась сама.
  void exit([int code = 0]) => _finish(code);

  void _finish(int code) {
    if (!_exit.isCompleted) {
      _exit.complete(code);
    }
    _output.close();
  }
}
