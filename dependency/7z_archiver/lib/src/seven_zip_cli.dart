import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';

import 'seven_zip_listing.dart';

/// Программа 7-Zip: где она лежит, как её звать и что значат её ответы.
///
/// Одна на приложение — модуль объявляет её службой. Дело не в экономии:
/// программа учится по ходу (какие ключи она понимает), и учиться заново на
/// каждом архиве незачем.
class SevenZipCli {
  SevenZipCli({required ProcessRunner processes, String? executable})
    : _processes = processes,
      _configured = executable;

  final ProcessRunner _processes;

  /// Путь из настроек модуля; пусто — искать самим.
  final String? _configured;

  /// Имена, под которыми программа встречается: официальная сборка 7-Zip,
  /// p7zip и его урезанный вариант.
  static const List<String> candidates = ['7zz', '7z', '7za'];

  /// Где смотреть, кроме PATH. Приложение, запущенное из Finder, наследует
  /// системный PATH без Homebrew — и программа, прекрасно видимая в терминале,
  /// из приложения не находится вовсе.
  static const List<String> wellKnownDirectories = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin'];

  String? _executable;
  bool _searched = false;

  /// Программа понимает `-spd`. Выясняется на первом же вызове: ключ есть не
  /// во всех сборках, а без него имя записи вроде `[1].txt` будет понято как
  /// образец для подстановки.
  bool _literalNames = true;

  /// Ключи, которые идут в каждый вызов.
  ///
  /// `-y` — отвечать «да»: вопрос о перезаписи иначе ждёт ответа.
  /// `-p` — пустой пароль: без него архив с паролем спрашивает его в stdin и
  /// подвешивает работу. Пустой пароль не подойдёт, и программа честно
  /// ошибётся — это лучше, чем зависнуть.
  static const List<String> _always = ['-y', '-p'];

  /// Путь к программе; бросает, если её нет.
  Future<String> resolve() async {
    if (_searched) {
      final found = _executable;
      if (found == null) {
        throw const FsError('7-Zip — install p7zip or set its path in settings', FsErrorKind.notFound);
      }
      return found;
    }

    _searched = true;

    final configured = _configured;
    if (configured != null && configured.isNotEmpty) {
      _executable = await _processes.which(configured, extraDirectories: wellKnownDirectories);
    } else {
      for (final name in candidates) {
        _executable = await _processes.which(name, extraDirectories: wellKnownDirectories);
        if (_executable != null) {
          break;
        }
      }
    }

    return resolve();
  }

  /// Установлена ли программа. Ошибки не бросает: спрашивают это там, где
  /// отсутствие — обычный ответ, а не беда.
  Future<bool> get available async {
    try {
      await resolve();
      return true;
    } on FsError {
      return false;
    }
  }

  /// Короткий вызов: дождаться конца и забрать вывод.
  Future<ProcessOutcome> run(List<String> arguments, {String? workingDirectory}) async {
    final executable = await resolve();
    final outcome = await _processes.run(executable, [..._always, ...arguments], workingDirectory: workingDirectory);

    if (outcome.exitCode == _commandLineError && _literalNames) {
      // Сборка не знает `-spd`. Учимся один раз и повторяем без него.
      _literalNames = false;
      return _processes.run(
        executable,
        [..._always, ...arguments]..remove(_literal),
        workingDirectory: workingDirectory,
      );
    }

    return outcome;
  }

  /// Длинный вызов: читать вывод по мере поступления.
  Future<ProcessSession> start(List<String> arguments, {String? workingDirectory}) async {
    final executable = await resolve();
    return _processes.start(executable, [..._always, ...arguments], workingDirectory: workingDirectory);
  }

  /// Ключ запрета подстановок — если сборка его понимает.
  List<String> get literalNames => _literalNames ? const [_literal] : const [];

  static const String _literal = '-spd';

  /// Оглавление архива.
  Future<SevenZipListing> list(String archivePath) async {
    final outcome = await run(['l', '-slt', ...literalNames, '--', archivePath]);

    if (!_ok(outcome.exitCode)) {
      throw errorOf(archivePath, outcome.exitCode, outcome.stderr);
    }

    return parseSevenZipListing(outcome.stdout);
  }

  /// Содержимое одной записи потоком.
  ///
  /// Ход работы отключён (`-bsp0`) и сообщения тоже (`-bso0`): данные идут в
  /// тот же поток, и проценты оказались бы посреди файла.
  Stream<List<int>> read(String archivePath, String entryName) async* {
    final session = await start(['x', '-so', '-bso0', '-bsp0', ...literalNames, '--', archivePath, entryName]);

    // Второй поток нужно читать, даже если он не нужен: программа, чей вывод
    // никто не забирает, встанет на заполненном канале.
    final complaints = StringBuffer();
    final watching = session.stderr.transform(const Utf8Decoder(allowMalformed: true)).forEach(complaints.write);

    try {
      yield* session.stdout;

      final code = await session.exitCode;
      await watching;
      if (!_ok(code)) {
        throw errorOf(entryName, code, complaints.toString());
      }
    } finally {
      // Читатель мог уйти раньше — закрыть панель посреди распаковки можно.
      // Программу, оставшуюся без слушателя, надо остановить.
      await session.kill();
    }
  }

  /// Ноль — успех, единица — предупреждение: часть файлов пропущена, но работа
  /// сделана. Считать предупреждение провалом нельзя.
  bool _ok(int exitCode) => exitCode == 0 || exitCode == _warning;

  static const int _warning = 1;
  static const int _commandLineError = 7;

  /// Что стоит за неудачей программы.
  ///
  /// Разбирается по тексту: кодов возврата всего шесть, и «ошибка» среди них
  /// одна на все случаи. Текст же программа печатает внятный.
  static FsError errorOf(String path, int exitCode, String stderr) {
    final text = stderr.toLowerCase();

    if (text.contains('wrong password') || text.contains('encrypted')) {
      return FsError(path, FsErrorKind.permissionDenied, stderr);
    }
    if (text.contains('can not open') || text.contains('cannot open') || text.contains('is not supported archive')) {
      return FsError(path, FsErrorKind.io, stderr);
    }
    if (exitCode == _outOfMemory) {
      return FsError(path, FsErrorKind.io, 'not enough memory');
    }

    return FsError(path, FsErrorKind.io, stderr.isEmpty ? 'exit code $exitCode' : stderr);
  }

  static const int _outOfMemory = 8;
}
