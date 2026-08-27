import 'dart:convert';
import 'dart:typed_data';

/// Что кладём в архив: файл, каталог или ссылка.
enum TarItemKind { file, directory, link }

/// Одна запись будущего архива.
///
/// Содержимое приходит потоком и **не читается заранее**: tar пишется подряд,
/// и держать в памяти нечего.
class TarItem {
  TarItem.file({required this.name, required this.size, required this.content, this.mode = 0x1a4, this.modified})
    : kind = TarItemKind.file,
      linkTarget = '';

  TarItem.directory({required this.name, this.mode = 0x1ed, this.modified})
    : kind = TarItemKind.directory,
      size = 0,
      content = null,
      linkTarget = '';

  TarItem.link({required this.name, required this.linkTarget, this.mode = 0x1ff, this.modified})
    : kind = TarItemKind.link,
      size = 0,
      content = null;

  /// Имя внутри архива, всегда с косой чертой: у каталога — с ней на конце.
  final String name;

  final TarItemKind kind;
  final int size;
  final int mode;
  final DateTime? modified;

  /// Куда ведёт ссылка; пусто — это не ссылка.
  final String linkTarget;

  /// Откуда взять содержимое; null у каталога и ссылки.
  final Stream<List<int>>? content;
}

/// Блок формата: заголовок и добивка — всегда по 512 байт.
const int _blockSize = 512;

/// Сколько имени помещается в сам заголовок.
const int _nameField = 100;

/// Собирает архив потоком: заголовок, содержимое, добивка — и так по кругу.
///
/// Ничего не копится в памяти и ничего не пишется на диск дважды: сжатие (для
/// `.tar.gz`) навешивается снаружи на этот же поток, поэтому промежуточного
/// файла не появляется вовсе.
///
/// [onEntry] зовётся перед записью, [onBytes] — по мере того, как уходит
/// содержимое: движение видно и внутри одного большого файла.
Stream<List<int>> writeTarStream(
  Stream<TarItem> items, {
  void Function(TarItem item)? onEntry,
  void Function(int bytes)? onBytes,
  Future<void> Function()? checkpoint,
}) async* {
  await for (final item in items) {
    await checkpoint?.call();
    onEntry?.call(item);

    // Длинное имя не влезает в заголовок и потому кладётся отдельной записью
    // перед ним — так делает GNU tar, и так же его читают все остальные.
    final nameBytes = utf8.encode(item.name);
    if (nameBytes.length > _nameField) {
      yield _header(
        name: '././@LongLink',
        size: nameBytes.length + 1,
        mode: 0,
        modified: null,
        type: 'L',
        linkTarget: '',
      );
      yield* _content(Stream<List<int>>.value([...nameBytes, 0]), nameBytes.length + 1);
    }

    yield _header(
      name: item.name,
      size: item.size,
      mode: item.mode,
      modified: item.modified,
      type: switch (item.kind) {
        TarItemKind.file => '0',
        TarItemKind.directory => '5',
        TarItemKind.link => '2',
      },
      linkTarget: item.linkTarget,
    );

    final content = item.content;
    if (content == null) {
      continue;
    }

    var written = 0;
    await for (final chunk in content) {
      await checkpoint?.call();
      written += chunk.length;
      onBytes?.call(chunk.length);
      yield chunk;
    }

    // Размер объявлен в заголовке, и разойтись с содержимым он не может: файл
    // могли дописать или обрезать, пока мы шли по дереву.
    if (written < item.size) {
      yield Uint8List(item.size - written);
    }
    yield* _padding(item.size);
  }

  // Архив кончается двумя нулевыми блоками — по ним читающий и понимает, что
  // записи закончились, а не оборвались.
  yield Uint8List(_blockSize * 2);
}

Stream<List<int>> _content(Stream<List<int>> source, int size) async* {
  yield* source;
  yield* _padding(size);
}

Stream<List<int>> _padding(int size) async* {
  final remainder = size % _blockSize;
  if (remainder != 0) {
    yield Uint8List(_blockSize - remainder);
  }
}

/// Заголовок записи в формате ustar.
Uint8List _header({
  required String name,
  required int size,
  required int mode,
  required DateTime? modified,
  required String type,
  required String linkTarget,
}) {
  final header = Uint8List(_blockSize);

  // Имя длиннее поля обрезается: полное лежит в отдельной записи перед этой.
  _putString(header, 0, _nameField, name);
  _putOctal(header, 100, 8, mode & 0xfff);
  _putOctal(header, 108, 8, 0);
  _putOctal(header, 116, 8, 0);
  _putOctal(header, 124, 12, size);
  _putOctal(header, 136, 12, (modified ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000);
  _putString(header, 156, 1, type);
  _putString(header, 157, 100, linkTarget);
  _putString(header, 257, 6, 'ustar');
  _putString(header, 263, 2, '00');

  // Сумма считается по заголовку, в котором её поле заполнено пробелами, —
  // и только потом на её место кладётся ответ.
  for (var i = 148; i < 156; i++) {
    header[i] = 0x20;
  }
  var checksum = 0;
  for (final byte in header) {
    checksum += byte;
  }
  // Поле суммы устроено не как остальные восьмеричные: шесть знаков, ноль и
  // пробел. Записать его общим способом (семь знаков и ноль) — значит потерять
  // последний знак, и архив перестаёт быть архивом: `tar` отвечает
  // «Unrecognized archive format».
  _putString(header, 148, 6, checksum.toRadixString(8).padLeft(6, '0'));
  header[154] = 0;
  header[155] = 0x20;

  return header;
}

void _putString(Uint8List header, int offset, int length, String value) {
  final bytes = utf8.encode(value);
  final count = bytes.length > length ? length : bytes.length;
  header.setRange(offset, offset + count, bytes);
}

void _putOctal(Uint8List header, int offset, int length, int value) {
  // Восьмеричное число в w-1 знаках с ведущими нулями и нулём на конце.
  final text = value.toRadixString(8).padLeft(length - 1, '0');
  _putString(header, offset, length - 1, text.substring(text.length - (length - 1)));
  header[offset + length - 1] = 0;
}
