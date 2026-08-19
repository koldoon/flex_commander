import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:fc_api/fc_api.dart';

/// Запись оглавления архива: то, что о ней известно без распаковки.
///
/// Каталоги в zip — не обязательные записи, а соглашение об именах: `a/b.txt`
/// может лежать в архиве, где никакого `a/` нет вовсе. Поэтому каталоги здесь
/// достраиваются по путям, и у достроенного нет ни даты, ни прав.
class ZipEntry {
  ZipEntry({required this.name, required this.isDirectory, this.entryName = '', this.size = 0, this.modified})
    : mode = 0,
      encrypted = false;

  ZipEntry.file({
    required this.name,
    required this.entryName,
    required this.size,
    this.modified,
    this.mode = 0,
    this.encrypted = false,
  }) : isDirectory = false;

  ZipEntry.directory({required this.name, this.entryName = '', this.modified, this.mode = 0})
    : isDirectory = true,
      size = 0,
      encrypted = false;

  /// Имя внутри родительского каталога.
  final String name;

  /// Полное имя записи в архиве — по нему запись и читается.
  final String entryName;

  final bool isDirectory;
  final int size;
  final DateTime? modified;

  /// Права доступа из архива; 0 — их там не было.
  final int mode;

  /// Содержимое зашифровано — читать его без пароля бессмысленно.
  ///
  /// Признак читается из оглавления **своими силами**: библиотека его наружу
  /// не отдаёт, а без него неверный пароль не отличить от битого архива.
  /// ZipCrypto к тому же не сообщает о неверном пароле вовсе — распаковщик
  /// просто давится зашифрованными байтами («Filter error, bad data»), и по
  /// одной этой ошибке спрашивать пароль значило бы спрашивать его и на
  /// испорченном архиве.
  final bool encrypted;

  final Map<String, ZipEntry> children = {};

  @override
  String toString() => entryName.isEmpty ? name : entryName;
}

/// Оглавление архива деревом.
class ZipIndex {
  ZipIndex(this.root);

  final ZipEntry root;

  /// Запись по разобранному на части пути; null — такой в архиве нет.
  ZipEntry? at(List<String> segments) {
    var entry = root;
    for (final name in segments) {
      final child = entry.children[name];
      if (child == null) {
        return null;
      }
      entry = child;
    }
    return entry;
  }
}

/// Подпись в начале файла: локальный заголовок записи, оглавление пустого
/// архива и маркер многотомного.
const int _localHeader = 0x504b0304;
const int _endOfDirectory = 0x504b0506;
const int _spanned = 0x504b0708;

/// Читает оглавление архива и строит по нему дерево.
///
/// Читается только оглавление: содержимое записей не распаковывается, поэтому
/// открытие архива стоит одного прохода по концу файла, а не всего архива.
///
/// Не-архив декодер молча объявляет пустым — поэтому файл сначала проверяется
/// по подписи, а потом ещё раз по результату: если подпись говорит, что записи
/// есть, а прочитать не удалось ни одной, значит оглавление не прочиталось.
/// Пустая панель вместо ошибки — худшее, чем может кончиться открытие.
Future<ZipIndex> readZipIndex(String archivePath) async {
  final signature = await _signatureOf(archivePath);
  if (signature != _localHeader && signature != _endOfDirectory && signature != _spanned) {
    throw FsError(archivePath, FsErrorKind.io);
  }

  final encrypted = await readEncryptedNames(archivePath);
  final input = InputFileStream(archivePath);

  try {
    final archive = ZipDecoder().decodeStream(input);
    if (archive.files.isEmpty && signature != _endOfDirectory) {
      throw FsError(archivePath, FsErrorKind.io);
    }

    final root = ZipEntry.directory(name: '/');

    for (final file in archive.files) {
      final segments = file.name.split('/').where((name) => name.isNotEmpty && name != '.').toList();
      if (segments.isEmpty) {
        continue;
      }

      var parent = root;
      // Всё, кроме последней части, — каталоги; те, которых нет в архиве
      // отдельной записью, достраиваются здесь.
      for (final name in segments.take(segments.length - 1)) {
        parent = parent.children.putIfAbsent(name, () => ZipEntry.directory(name: name));
      }

      final name = segments.last;
      if (file.isDirectory) {
        parent.children.putIfAbsent(
          name,
          () => ZipEntry.directory(name: name, entryName: file.name, modified: file.lastModDateTime, mode: file.mode),
        );
        continue;
      }

      // Одноимённая запись в архиве бывает: побеждает последняя, как при
      // распаковке.
      parent.children[name] = ZipEntry.file(
        name: name,
        entryName: file.name,
        encrypted: encrypted.contains(file.name),
        size: file.size,
        modified: file.lastModDateTime,
        mode: file.mode,
      );
    }

    return ZipIndex(root);
  } on ArchiveException catch (error) {
    // Битый архив — это отказ открыть, а не пустой каталог.
    throw FsError(archivePath, FsErrorKind.io, error);
  } on FormatException catch (error) {
    throw FsError(archivePath, FsErrorKind.io, error);
  } finally {
    await input.close();
  }
}

/// Подпись записи оглавления и его конца.
const int _centralHeader = 0x02014b50;
const int _endOfCentralRecord = 0x06054b50;

/// Имена записей, у которых поднят признак шифрования.
///
/// Оглавление разбирается своими силами: `package:archive` этот бит наружу не
/// отдаёт, а знать его нужно **до** чтения — иначе неверный пароль неотличим от
/// испорченного архива, а у ZipCrypto он и вовсе ничем себя не выдаёт.
///
/// Разбор бережный: не нашли конец оглавления, не сошлась подпись, встретился
/// zip64 — возвращается пустое множество. Это значит «не знаем», и провайдер
/// поведёт себя как раньше; врать про шифрование хуже, чем промолчать.
Future<Set<String>> readEncryptedNames(String archivePath) async {
  final file = await File(archivePath).open();

  try {
    final length = await file.length();
    // Конец оглавления лежит в хвосте: 22 байта плюс комментарий (до 64 КиБ).
    final tailSize = math.min(length, 22 + 0xFFFF);
    await file.setPosition(length - tailSize);
    final tail = await file.read(tailSize);

    final end = _lastSignature(tail, _endOfCentralRecord);
    if (end < 0 || end + 20 > tail.length) {
      return const {};
    }

    final endView = ByteData.sublistView(tail);
    final count = endView.getUint16(end + 10, Endian.little);
    final size = endView.getUint32(end + 12, Endian.little);
    final offset = endView.getUint32(end + 16, Endian.little);
    if (size == 0xFFFFFFFF || offset == 0xFFFFFFFF || offset + size > length) {
      // zip64 или неправдоподобные числа: молчим.
      return const {};
    }

    await file.setPosition(offset);
    return _encryptedIn(await file.read(size), count);
  } on FileSystemException {
    return const {};
  } finally {
    await file.close();
  }
}

Set<String> _encryptedIn(Uint8List central, int count) {
  final names = <String>{};
  final view = ByteData.sublistView(central);
  var at = 0;

  for (var i = 0; i < count && at + 46 <= central.length; i++) {
    if (view.getUint32(at, Endian.little) != _centralHeader) {
      break;
    }

    final flags = view.getUint16(at + 8, Endian.little);
    final nameLength = view.getUint16(at + 28, Endian.little);
    final extraLength = view.getUint16(at + 30, Endian.little);
    final commentLength = view.getUint16(at + 32, Endian.little);
    if (at + 46 + nameLength > central.length) {
      break;
    }

    // Первый бит общих признаков и означает «содержимое зашифровано».
    if (flags & 0x1 != 0) {
      names.add(utf8.decode(central.sublist(at + 46, at + 46 + nameLength), allowMalformed: true));
    }

    at += 46 + nameLength + extraLength + commentLength;
  }

  return names;
}

/// Последнее вхождение подписи; -1 — не нашлось.
int _lastSignature(Uint8List bytes, int signature) {
  for (var at = bytes.length - 4; at >= 0; at--) {
    if (ByteData.sublistView(bytes).getUint32(at, Endian.little) == signature) {
      return at;
    }
  }
  return -1;
}

/// Первые четыре байта файла. 0 — файл короче или не читается.
Future<int> _signatureOf(String path) async {
  try {
    final file = await File(path).open();
    try {
      final bytes = await file.read(4);
      if (bytes.length < 4) {
        return 0;
      }
      return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
    } finally {
      await file.close();
    }
  } on FileSystemException catch (error) {
    throw FsError(path, FsErrorKind.io, error);
  }
}
