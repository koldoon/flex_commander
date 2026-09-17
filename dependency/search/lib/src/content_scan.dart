import 'dart:convert';
import 'dart:typed_data';

import 'content_rule.dart';

/// Чтение файла кусками с поиском внутри.
///
/// Куском, а не целиком: файл бывает больше памяти (`docs/spec/file-search.md`,
/// §11.3). Состояние живёт здесь, потому что **между кусками его и надо
/// держать**: хвост байт на стык и недочитанная строка для выражения.
class ContentScan {
  ContentScan(this.rule);

  final ContentRule rule;

  /// Хвост прошлого куска: последние `длина образца − 1` байт.
  Uint8List _carry = Uint8List(0);

  /// Недочитанная строка — для выражения, которое ищется по тексту построчно.
  final StringBuffer _line = StringBuffer();

  /// Разбор UTF-8 **потоком**: знак бывает разорван границей чтения так же, как
  /// и образец, и разбирать каждый кусок отдельно значит ломать такие знаки —
  /// стенд поймал это первым же несовпадением.
  late final ByteConversionSink _bytes = const Utf8Decoder(
    allowMalformed: true,
  ).startChunkedConversion(_TextSink(_onText));

  bool _found = false;

  /// Нашлось ли — и, значит, читать дальше незачем.
  bool get found => _found;

  /// Очередной кусок. Возвращает `true`, когда совпадение уже найдено.
  bool feed(List<int> chunk) {
    if (_found || rule.isEmpty || !rule.isValid) {
      return _found;
    }
    if (rule.regexp) {
      _bytes.add(chunk);
      return _found;
    }
    _feedBytes(chunk);
    return _found;
  }

  /// Кусков больше не будет: дочитать то, что осталось в руках.
  bool close() {
    if (_found || !rule.regexp || rule.isEmpty || !rule.isValid) {
      return _found;
    }
    _bytes.close();
    if (_found) {
      return true;
    }
    // Последняя строка приходит без перевода строки — искать в ней всё равно
    // надо.
    final rest = _line.toString();
    _line.clear();
    if (rest.isNotEmpty && rule.matchesText(rest)) {
      _found = true;
    }
    return _found;
  }

  void _feedBytes(List<int> chunk) {
    // Хвост приклеивается **спереди**: совпадение, разорванное границей чтения,
    // иначе пропадает молча.
    final joined =
        Uint8List(_carry.length + chunk.length)
          ..setRange(0, _carry.length, _carry)
          ..setRange(_carry.length, _carry.length + chunk.length, chunk);

    if (rule.matchesBytes(joined)) {
      _found = true;
      _carry = Uint8List(0);
      return;
    }

    final tail = rule.tail;
    if (tail <= 0 || joined.length <= tail) {
      _carry = joined;
      return;
    }
    _carry = Uint8List.sublistView(joined, joined.length - tail);
  }

  /// Разобранный текст — по мере того, как он разбирается.
  void _onText(String piece) {
    if (_found) {
      return;
    }
    _line.write(piece);
    final whole = _line.toString();
    final lines = whole.split('\n');
    // Последняя часть — не строка, а её начало: она дожидается своего перевода.
    for (var at = 0; at < lines.length - 1; at++) {
      if (rule.matchesText(lines[at])) {
        _found = true;
        _line.clear();
        return;
      }
    }
    _line
      ..clear()
      ..write(lines.last);
    // Строка без конца не должна расти бесконечно: файл в один гигабайт без
    // единого перевода строки — это не текст, а повод остановиться.
    if (_line.length > lineLimit) {
      final kept = _line.toString();
      _line
        ..clear()
        ..write(kept.substring(kept.length - keptOnLongLine));
    }
  }

  /// Докуда растёт строка без перевода.
  static const int lineLimit = 1 << 20;

  /// Сколько от неё остаётся, когда предел превышен: столько же, сколько
  /// переносится между кусками у байтового поиска, — по той же причине.
  static const int keptOnLongLine = 4096;
}

/// Куда потоковый разбор складывает разобранное.
class _TextSink implements Sink<String> {
  _TextSink(this._onText);

  final void Function(String piece) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}
