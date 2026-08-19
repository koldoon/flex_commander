import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';

/// Один запуск программы: что позвали и с чем.
class ProcessCall {
  const ProcessCall(this.executable, this.arguments, {this.workingDirectory});

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  /// Аргументы одной строкой — так их удобнее искать в проверках.
  String get commandLine => arguments.join(' ');

  /// Команда программы: первый аргумент, который не ключ. Ключи идут вперемешку
  /// с ней, и «первый аргумент» командой не является.
  String get command => arguments.firstWhere((argument) => !argument.startsWith('-'), orElse: () => '');

  /// Есть ли среди аргументов такой — точным совпадением, а не подстрокой.
  bool has(String argument) => arguments.contains(argument);

  @override
  String toString() => '$executable $commandLine';
}

/// Что подставная программа ответит на вызов.
class FakeProcessReply {
  const FakeProcessReply({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
    this.stdoutChunks,
    this.holds = false,
  });

  /// Программа, которая не заканчивается сама: код возврата придёт только
  /// после [ProcessSession.kill]. Так проверяется отмена.
  const FakeProcessReply.running({this.stdout = '', this.stdoutChunks}) : exitCode = 0, stderr = '', holds = true;

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Вывод кусками — когда важно, что он течёт, а не приходит разом.
  /// Пусто — весь [stdout] уходит одним куском.
  final List<List<int>>? stdoutChunks;

  /// Ждать, пока не убьют.
  final bool holds;

  List<List<int>> get _chunks => stdoutChunks ?? (stdout.isEmpty ? const [] : [utf8.encode(stdout)]);
}

/// Подставной запускатель программ.
///
/// Тесты модуля, стоящего над внешним инструментом, не должны требовать этого
/// инструмента на машине: иначе они проходят у одного и падают у другого.
/// Здесь программа отвечает по сценарию, а все её вызовы записываются — так
/// проверяется и результат, и то, с какими ключами её позвали.
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner({this.reply, Map<String, String>? executables})
    : executables = executables ?? const {'7z': '/usr/bin/7z', '7zz': '/usr/bin/7zz'};

  /// Ответ на вызов. Пусто — успех без вывода.
  final FakeProcessReply Function(ProcessCall call)? reply;

  /// Что лежит в PATH: имя → путь. Пустая карта означает машину, где нет
  /// ничего, — на ней проверяется поведение без установленной программы.
  final Map<String, String> executables;

  /// Все вызовы по порядку.
  final List<ProcessCall> calls = [];

  /// Незавершённые запуски: их можно убить из теста, если этого не сделал код.
  final List<FakeProcessSession> sessions = [];

  ProcessCall get lastCall => calls.last;

  /// Вызовы с этой командой (`l`, `a`, `d`, `x`).
  List<ProcessCall> callsOf(String command) => calls.where((call) => call.command == command).toList();

  @override
  Future<ProcessOutcome> run(String executable, List<String> arguments, {String? workingDirectory}) async {
    final answer = _answer(ProcessCall(executable, arguments, workingDirectory: workingDirectory));
    return ProcessOutcome(
      exitCode: answer.exitCode,
      stdout: answer.stdoutChunks == null ? answer.stdout : utf8.decode(answer._chunks.expand((c) => c).toList()),
      stderr: answer.stderr,
    );
  }

  @override
  Future<ProcessSession> start(String executable, List<String> arguments, {String? workingDirectory}) async {
    final answer = _answer(ProcessCall(executable, arguments, workingDirectory: workingDirectory));
    final session = FakeProcessSession(answer);
    sessions.add(session);
    return session;
  }

  @override
  Future<String?> which(String executable, {Iterable<String> extraDirectories = const []}) async =>
      executables[executable];

  FakeProcessReply _answer(ProcessCall call) {
    calls.add(call);
    return reply?.call(call) ?? const FakeProcessReply();
  }
}

/// Запущенная подставная программа.
class FakeProcessSession implements ProcessSession {
  FakeProcessSession(this._reply) {
    if (!_reply.holds) {
      _exitCode.complete(_reply.exitCode);
    }
  }

  final FakeProcessReply _reply;
  final Completer<int> _exitCode = Completer<int>();

  /// Программу убили: так проверяется, что отмена дошла до процесса.
  bool killed = false;

  @override
  Stream<List<int>> get stdout => Stream.fromIterable(_reply._chunks);

  @override
  Stream<List<int>> get stderr =>
      _reply.stderr.isEmpty ? const Stream.empty() : Stream.value(utf8.encode(_reply.stderr));

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<void> kill() async {
    killed = true;
    if (!_exitCode.isCompleted) {
      // 255 — то, чем 7-Zip отвечает на прерывание пользователем.
      _exitCode.complete(255);
    }
  }
}
