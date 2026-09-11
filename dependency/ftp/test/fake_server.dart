import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Крошечный FTP-сервер для проверок клиента.
///
/// Настоящие сокеты и настоящий канал данных: проверять разговор двух сторон
/// подставкой над самим разговором — значит не проверять ничего. Живой сервер
/// (`docs/spec/ftp.md`, §13) отвечает на другой вопрос: верны ли наши
/// предположения о **чужом** сервере; этот отвечает, правильно ли мы говорим.
///
/// Умеет ровно то, что нужно клиенту, и нарочно умеет это по-разному: баннер в
/// несколько строк, `EPSV` или `PASV` на выбор, `MLSD` или только `LIST`.
class FakeFtpServer {
  FakeFtpServer._(this._socket, this.files, {required this.machineListing, required this.extendedPassive});

  /// Сколько сервер ждёт закрытия со стороны клиента, прежде чем досылать
  /// хвост сам. У настоящего это секунды; здесь ровно столько, чтобы неверный
  /// клиент было видно по времени, а прогон не стоял.
  static const Duration lingerGuard = Duration(seconds: 3);

  /// Скольким ближайшим передачам отказать переходной ошибкой `425`.
  ///
  /// Так живая сеть и отвечает, когда канал данных не задался: это не «нет
  /// файла» и не «нет доступа», а «попробуйте ещё раз»
  /// (`docs/spec/ftp.md`, §3.7).
  int refuseTransfers = 0;

  final ServerSocket _socket;

  /// Содержимое: путь → строки списка (для каталога) или байты (для файла).
  final Map<String, Object> files;

  /// Отвечать ли на `MLSD`; false — только `LIST`, как старые серверы.
  final bool machineListing;

  /// Понимать ли `EPSV`; false — только `PASV`.
  final bool extendedPassive;

  /// Команды, которые дошли до сервера, — по порядку и без доводов у `PASS`.
  final List<String> commands = [];

  int get port => _socket.port;

  static Future<FakeFtpServer> start({
    Map<String, Object> files = const {},
    bool machineListing = true,
    bool extendedPassive = true,
  }) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = FakeFtpServer._(
      socket,
      {...files},
      machineListing: machineListing,
      extendedPassive: extendedPassive,
    );
    socket.listen(server._serve);
    return server;
  }

  Future<void> stop() => _socket.close();

  void _serve(Socket control) {
    unawaited(_Session(this, control).run());
  }
}

class _Session {
  _Session(this.server, this.control);

  final FakeFtpServer server;
  final Socket control;

  ServerSocket? _data;
  Future<Socket>? _pending;

  /// Смещение, заданное `REST`.
  int _restart = 0;

  void say(String line) => control.add(utf8.encode('$line\r\n'));

  Future<void> run() async {
    // Баннер в несколько строк — тот самый случай, на котором ломается наивный
    // разбор ответа (`docs/spec/ftp.md`, §3.1).
    say('220-Добро пожаловать');
    // Четвёртый символ — пробел: наивный разбор считает такую строку концом
    // ответа и дальше врёт весь сеанс.
    say('    строка, похожая на конец ответа');
    say('220 Готов');

    final lines = control.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
    await for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final space = line.indexOf(' ');
      final command = (space < 0 ? line : line.substring(0, space)).toUpperCase();
      final argument = space < 0 ? '' : line.substring(space + 1);
      server.commands.add(command == 'PASS' ? 'PASS' : line);

      if (await _handle(command, argument)) {
        break;
      }
    }
    control.destroy();
  }

  Future<bool> _handle(String command, String argument) async {
    switch (command) {
      case 'USER':
        say('331 Нужен пароль');
      case 'PASS':
        say('230 Вход выполнен');
      case 'FEAT':
        say('211-Features:');
        if (server.machineListing) {
          say(' MLST modify*;size*;type*;');
        }
        if (server.extendedPassive) {
          say(' EPSV');
        }
        say(' REST STREAM');
        say(' SIZE');
        say(' UTF8');
        say('211 End');
      case 'OPTS':
        say('200 Принято');
      case 'TYPE':
        say('200 Режим ${argument.trim()}');
      case 'PWD':
        say('257 "/" is the current directory');
      case 'EPSV':
        if (!server.extendedPassive) {
          say('500 Не понимаю');
        } else {
          final port = await _listen();
          say('229 Entering Extended Passive Mode (|||$port|)');
        }
      case 'PASV':
        final port = await _listen();
        say('227 Entering Passive Mode (127,0,0,1,${port ~/ 256},${port % 256})');
      case 'REST':
        _restart = int.tryParse(argument) ?? 0;
        say('350 Продолжу с $_restart');
      case 'SIZE':
        final content = server.files[argument];
        if (content is List<int>) {
          say('213 ${content.length}');
        } else {
          say('550 $argument: нет такого файла');
        }
      case 'MLSD':
      case 'LIST':
        if (command == 'MLSD' && !server.machineListing) {
          say('500 Не понимаю');
        } else {
          await _sendLines(command, argument);
        }
      case 'RETR':
        await _sendBytes(argument);
      case 'STOR':
        await _receive(argument);
      case 'MKD':
        server.files['$argument/'] = <String>[];
        say('257 "$argument" создан');
      case 'DELE':
      case 'RMD':
        if (server.files.remove(argument) == null && server.files.remove('$argument/') == null) {
          say('550 $argument: нет такого');
        } else {
          say('250 Удалено');
        }
      case 'RNFR':
        _renameFrom = argument;
        say('350 Жду новое имя');
      case 'RNTO':
        final from = _renameFrom;
        final content = from == null ? null : server.files.remove(from);
        if (content == null) {
          say('550 $argument: нечего переименовывать');
        } else {
          server.files[argument] = content;
          say('250 Переименовано');
        }
      case 'ABOR':
        say('226 Прервано');
      case 'QUIT':
        say('221 До свидания');
        return true;
      default:
        say('502 Команда не поддержана');
    }
    return false;
  }

  String? _renameFrom;

  Future<int> _listen() async {
    await _data?.close();
    final data = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _data = data;
    _pending = data.first;
    return data.port;
  }

  Future<Socket> _accept() async {
    final pending = _pending;
    if (pending == null) {
      throw StateError('Канал данных не открыт');
    }
    _pending = null;
    return pending;
  }

  Future<void> _sendLines(String command, String path) async {
    final content = server.files[path] ?? server.files['$path/'];
    if (content is! List<String>) {
      say('550 $path: нет такого каталога');
      return;
    }
    if (server.refuseTransfers > 0) {
      server.refuseTransfers--;
      // Передачи не было вовсе — значит и хвоста не будет.
      say('425 Канал данных не открылся');
      return;
    }
    final socket = await _accept();
    say('150 Открываю канал для $command');
    for (final line in content) {
      socket.add(utf8.encode('$line\r\n'));
    }
    await socket.flush();
    await socket.close();
    await _awaitClientClose(socket);
    say('226 Передача закончена');
  }

  /// Дождаться, пока клиент закроет свою половину канала данных.
  ///
  /// **Настоящий сервер ведёт себя именно так**: `226` он досылает, когда
  /// закрылись обе стороны, а не своя. Клиент, который этого не делает, ждёт
  /// сервера до его собственного таймаута — десять секунд на каждый каталог,
  /// сколько бы в нём ни было файлов (`docs/spec/ftp.md`, §3.8).
  ///
  /// Предел здесь затем, чтобы неверный клиент проверку **замедлял**, а не
  /// вешал: разница видна по времени.
  Future<void> _awaitClientClose(Socket socket) async {
    try {
      await socket.listen(null).asFuture<void>().timeout(FakeFtpServer.lingerGuard);
    } on Object {
      // Не дождались — ведём себя как настоящий сервер: досылаем хвост сами.
    }
  }

  Future<void> _sendBytes(String path) async {
    final content = server.files[path];
    if (content is! List<int>) {
      say('550 $path: нет такого файла');
      _restart = 0;
      return;
    }
    final socket = await _accept();
    say('150 Открываю канал для RETR');
    socket.add(content.sublist(_restart.clamp(0, content.length)));
    _restart = 0;
    await socket.flush();
    await socket.close();
    await _awaitClientClose(socket);
    say('226 Передача закончена');
  }

  Future<void> _receive(String path) async {
    final socket = await _accept();
    say('150 Открываю канал для STOR');
    final bytes = <int>[];
    await for (final chunk in socket) {
      bytes.addAll(chunk);
    }
    server.files[path] = bytes;
    say('226 Принято');
  }
}
