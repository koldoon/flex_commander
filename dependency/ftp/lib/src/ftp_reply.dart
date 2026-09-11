/// Ответ сервера: трёхзначный код и строки, из которых он состоит.
///
/// Значение, а не строка: по коду решают, что делать дальше, а текст идёт
/// человеку — он на языке сервера, и разбирать его нельзя
/// (`docs/spec/ftp.md`, §3.4).
class FtpReply {
  const FtpReply(this.code, this.lines);

  /// Трёхзначный код; 0 — сервер ответил тем, что кодом не является.
  final int code;

  /// Строки ответа целиком, включая первую и последнюю с кодом.
  final List<String> lines;

  /// Текст для человека: у однострочного — то, что после кода, у
  /// многострочного — середина, где сервер и рассказывает, что случилось.
  String get message {
    if (lines.length == 1) {
      final single = lines.single;
      // Кода нет — значит и отрезать нечего: строка целиком и есть сообщение.
      if (code == 0) {
        return single;
      }
      return single.length > 4 ? single.substring(4) : single;
    }
    return lines.sublist(1, lines.length - 1).join('\n').trim();
  }

  /// Первая цифра кода — род ответа: 1 предварительный, 2 готово,
  /// 3 продолжайте, 4 временная неудача, 5 отказ.
  int get kind => code ~/ 100;

  bool get isPositive => kind == 1 || kind == 2 || kind == 3;

  /// Готово: команда выполнена и продолжения не ждёт.
  bool get isComplete => kind == 2;

  /// Сервер открыл канал данных и ждёт передачи: `150`, `125`.
  bool get isAboutToTransfer => code == 150 || code == 125;

  @override
  String toString() => '$code ${message.replaceAll('\n', ' / ')}';
}

/// Сборка ответа по строкам — по RFC 959.
///
/// **Многострочный ответ кончается не любой строкой с пробелом на четвёртом
/// месте, а строкой с тем же кодом, что открыла ответ.** Разница не
/// умозрительная: приветствие настоящего сервера бывает баннером из ASCII-арта,
/// и в нём есть строки, которые наивная проверка принимает за конец ответа.
/// Первая же попытка прощупать сервер на этом и поехала
/// (`docs/spec/ftp.md`, §3.1).
///
/// Отдельным классом, а не функцией над списком строк: строки приходят из
/// сокета по одной, и решение «ответ дочитан» принимается на каждой.
class FtpReplyReader {
  final List<String> _lines = [];

  /// Код, которым открылся многострочный ответ; null — ответа не начинали или
  /// он однострочный.
  int? _pending;

  /// Ждём ли продолжения.
  bool get isWaiting => _pending != null;

  /// Принимает строку; возвращает ответ, если он дочитан, иначе null.
  FtpReply? add(String line) {
    _lines.add(line);

    final open = _pending;
    if (open == null) {
      final code = _codeOf(line);
      if (code == null) {
        // Строка без кода в начале ответа: сервер сказал что-то своё. Отдаём
        // как есть — молчать об этом хуже, чем показать.
        return _take(0);
      }
      if (_isLast(line)) {
        return _take(code);
      }
      _pending = code;
      return null;
    }

    // Внутри многострочного: конец — только строка того же кода с пробелом.
    if (_codeOf(line) == open && _isLast(line)) {
      return _take(open);
    }
    return null;
  }

  FtpReply _take(int code) {
    final reply = FtpReply(code, List.unmodifiable(_lines));
    _lines.clear();
    _pending = null;
    return reply;
  }

  /// Разделитель после кода: пробел — ответ кончился, дефис — продолжается.
  static bool _isLast(String line) => line.length >= 4 && line[3] == ' ';

  /// Трёхзначный код в начале строки; null — его там нет.
  static int? _codeOf(String line) {
    if (line.length < 4) {
      return null;
    }
    final separator = line[3];
    if (separator != ' ' && separator != '-') {
      return null;
    }
    for (var i = 0; i < 3; i++) {
      final digit = line.codeUnitAt(i);
      if (digit < 0x30 || digit > 0x39) {
        return null;
      }
    }
    return int.parse(line.substring(0, 3));
  }
}
