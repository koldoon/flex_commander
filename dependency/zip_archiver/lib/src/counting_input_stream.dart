import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Поток, который рассказывает, сколько из него уже прочитали.
///
/// Упаковщик читает запись сам — кусками по килобайту, — и без такой обёртки о
/// ходе внутри файла узнать неоткуда: единственное, что видно снаружи, это
/// «файл начался» и «файл кончился». На файле в несколько гигабайт это и есть
/// та самая полоса, которая не двигается.
///
/// Считаются **прочитанные байты, оба прохода**: запись вычитывается дважды —
/// сперва ради контрольной суммы, потом ради сжатия. Считать только первый
/// проход заманчиво (объём работы совпал бы с размером файла), но тогда полоса
/// заполнялась бы на быстром чтении и замирала на медленном сжатии — то есть
/// ровно там, где движение и нужно.
///
/// Перемотки и повторные чтения одного и того же места счёт не двигают: он
/// идёт по приросту позиции, а не по числу вызовов.
class CountingInputStream extends InputStream {
  CountingInputStream(this._inner, this.onBytes) : super(byteOrder: _inner.byteOrder);

  final InputStream _inner;

  /// Зовётся на каждый прочитанный кусок — с тем, насколько продвинулись.
  final void Function(int bytes) onBytes;

  /// Позиция, о которой уже отчитались.
  int _reported = 0;

  @override
  int get position => _inner.position;

  @override
  set position(int value) => _inner.position = value;

  @override
  int get length => _inner.length;

  @override
  bool get isEOS => _inner.isEOS;

  @override
  bool open() => _inner.open();

  @override
  Future<void> close() => _inner.close();

  @override
  void closeSync() => _inner.closeSync();

  @override
  void reset() {
    _inner.reset();
    // Начался следующий проход по той же записи — считаем его отдельно.
    _reported = _inner.position;
  }

  @override
  void setPosition(int value) {
    _inner.setPosition(value);
    _reported = _inner.position;
  }

  @override
  void rewind([int length = 1]) {
    _inner.rewind(length);
    _reported = _inner.position;
  }

  @override
  void skip(int length) {
    _inner.skip(length);
    _reported = _inner.position;
  }

  @override
  InputStream subset({int? position, int? length, int? bufferSize}) =>
      _inner.subset(position: position, length: length, bufferSize: bufferSize);

  @override
  int readByte() {
    final byte = _inner.readByte();
    _reportProgress();
    return byte;
  }

  @override
  InputStream readBytes(int count) {
    final bytes = _inner.readBytes(count);
    _reportProgress();
    return bytes;
  }

  @override
  Uint8List toUint8List() {
    final result = _inner.toUint8List();
    _reportProgress();
    return result;
  }

  void _reportProgress() {
    final position = _inner.position;
    if (position <= _reported) {
      return;
    }
    final advanced = position - _reported;
    _reported = position;
    onBytes(advanced);
  }
}
