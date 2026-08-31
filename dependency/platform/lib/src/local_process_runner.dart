import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:path/path.dart' as p;

/// Реализация [ProcessRunner] для настоящей системы: `dart:io` живёт здесь, а
/// не в API и не в модулях, которым нужна программа.
class LocalProcessRunner implements ProcessRunner {
  const LocalProcessRunner();

  @override
  Future<ProcessOutcome> run(String executable, List<String> arguments, {String? workingDirectory}) async {
    final session = await start(executable, arguments, workingDirectory: workingDirectory);

    // Оба потока читаются разом, а не по очереди: программа, чей второй канал
    // никто не забирает, встанет на его заполнении. Классический тупик, и
    // проявляется он только на выводе длиннее буфера канала.
    final output = await Future.wait([_text(session.stdout), _text(session.stderr)]);

    return ProcessOutcome(exitCode: await session.exitCode, stdout: output[0], stderr: output[1]);
  }

  @override
  Future<ProcessSession> start(String executable, List<String> arguments, {String? workingDirectory}) async {
    final Process process;
    try {
      process = await Process.start(executable, arguments, workingDirectory: workingDirectory);
    } on ProcessException catch (error) {
      throw FsError(executable, FsErrorKind.notFound, error);
    }

    // Ввод закрывается сразу. Программа, спросившая пароль или подтверждение,
    // иначе ждёт ответа вечно — и вместе с ней ждёт приложение. Это не
    // предположение: ровно так ведёт себя 7z на архиве с паролем.
    unawaited(process.stdin.close().catchError((Object _) {}));

    return _LocalProcessSession(process);
  }

  @override
  Future<String?> which(String executable, {Iterable<String> extraDirectories = const []}) async {
    if (executable.contains(Platform.pathSeparator)) {
      // Указали путь, а не имя: искать нечего, надо проверить.
      return _executableAt(executable);
    }

    final separator = Platform.isWindows ? ';' : ':';
    final fromPath = (Platform.environment['PATH'] ?? '').split(separator);

    for (final directory in [...fromPath, ...extraDirectories]) {
      if (directory.isEmpty) {
        continue;
      }
      for (final name in _candidateNames(executable)) {
        final found = _executableAt(p.join(directory, name));
        if (found != null) {
          return found;
        }
      }
    }

    return null;
  }

  /// Имена, под которыми программа может лежать: на Windows у неё есть
  /// расширение, и звать её по голому имени нельзя.
  Iterable<String> _candidateNames(String executable) {
    if (!Platform.isWindows) {
      return [executable];
    }
    final extensions = (Platform.environment['PATHEXT'] ?? '.EXE;.BAT;.CMD').split(';');
    return [executable, for (final extension in extensions) '$executable${extension.toLowerCase()}'];
  }

  /// Путь, если по нему лежит файл, который можно выполнить.
  String? _executableAt(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    if (Platform.isWindows) {
      return path;
    }
    // Бит выполнения хоть у кого-нибудь: каталог в PATH нередко содержит
    // одноимённый файл данных, и запускать его не нужно.
    return file.statSync().mode & 0x49 != 0 ? path : null;
  }

  Future<String> _text(Stream<List<int>> stream) {
    // С допуском на порчу: одно кривое имя в выводе не должно рушить разбор
    // всего остального.
    return stream.transform(const Utf8Decoder(allowMalformed: true)).join();
  }
}

class _LocalProcessSession implements ProcessSession {
  _LocalProcessSession(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> kill() async {
    // Уже завершившуюся убить нельзя, и это не ошибка: отмена и конец работы
    // вполне могут случиться в один момент.
    _process.kill();
  }
}
