import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';

/// Запись оглавления: то, что о ней известно из заголовка.
///
/// Каталоги в tar бывают отдельными записями, а бывают и нет — как в zip.
/// Достроенные по путям отличаются от настоящих тем, что у них нет ни даты,
/// ни прав.
class TarEntry {
  TarEntry.file({
    required this.name,
    required this.size,
    required this.offset,
    this.modified,
    this.mode = 0,
    this.linkTarget,
  }) : isDirectory = false;

  TarEntry.directory({required this.name, this.modified, this.mode = 0})
    : isDirectory = true,
      size = 0,
      offset = 0,
      linkTarget = null;

  /// Имя внутри родительского каталога.
  final String name;

  final bool isDirectory;

  final int size;

  /// Смещение содержимого в файле архива.
  ///
  /// Ради него оглавление и читается своими силами: в tar содержимое лежит
  /// несжатым и подряд, поэтому чтение записи — это один прыжок, а не проход
  /// по всему архиву заново.
  final int offset;

  final DateTime? modified;

  /// Права доступа из архива; 0 — их там не было.
  final int mode;

  /// Куда ведёт ссылка; null — это не ссылка.
  ///
  /// Права и ссылки — главное, чем tar отличается от zip, и причина, по
  /// которой мир Unix им пользуется.
  final String? linkTarget;

  final Map<String, TarEntry> children = {};

  @override
  String toString() => name;
}

/// Оглавление архива деревом.
class TarIndex {
  TarIndex(this.root);

  final TarEntry root;

  /// Запись по разобранному на части пути; null — такой в архиве нет.
  TarEntry? at(List<String> segments) {
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

/// Заголовок записи: ровно один блок.
const int _blockSize = 512;

/// Через сколько записей проход отдаёт управление.
///
/// Число из тех, что не выбираются точно: реже — и `Esc` начинает опаздывать,
/// чаще — и на архиве из мелочи каждый прыжок по событийному циклу стоит
/// дороже самого чтения заголовка.
const int _checkpointEvery = 512;

/// Типы записей, которые нас касаются.
const String _typeHardLink = '1';
const String _typeSymLink = '2';
const String _typeDirectory = '5';
const String _typeLongName = 'L';
const String _typeLongLink = 'K';
const String _typePaxFile = 'x';
const String _typePaxGlobal = 'g';

/// Читает оглавление архива и строит по нему дерево.
///
/// Оглавления у формата нет вовсе: записи лежат подряд, у каждой свой блок
/// заголовка. Значит, узнать, что внутри, можно только пройдя файл целиком —
/// зато содержимое при этом не читается ни разу: по размеру из заголовка мы
/// перепрыгиваем через него.
///
/// Не-tar объявляется ошибкой, а не пустым архивом: пустая панель вместо
/// ошибки — худшее, чем может кончиться открытие. Признак — контрольная сумма
/// заголовка: подписи у формата нет вовсе, и сумма остаётся единственным, по
/// чему его можно узнать.
///
/// А вот пустой архив — не ошибка: он весь состоит из нулевых блоков, и такой
/// делает сам `tar`. Отличить его от файла, начинающегося с нулей, нечем — они
/// побайтно одинаковы, и притворяться, что мы умеем, не стоит.
///
/// Проход синхронный: заголовки читаются вперемежку с прыжками через
/// содержимое, и асинхронности тут взяться неоткуда. Но архив из сотен тысяч
/// записей так листается секундами, а всё это время приложение не
/// перерисовывается и не слышит `Esc`. Поэтому каждые [_checkpointEvery]
/// записей проход отдаёт управление: [checkpoint] — это пауза и отмена,
/// [onEntries] — счётчик для вехи.
Future<TarIndex> readTarIndex(
  String archivePath, {
  Future<void> Function()? checkpoint,
  void Function(int entries)? onEntries,
}) async {
  final file = File(archivePath).openSync();

  try {
    final root = TarEntry.directory(name: '/');
    var position = 0;
    var seen = 0;

    // Длинные имена приходят отдельной записью **перед** той, к которой
    // относятся: и у GNU (`L`), и у PAX (`x`).
    String? pendingName;
    String? pendingLink;

    while (true) {
      if (++seen % _checkpointEvery == 0) {
        onEntries?.call(seen);
        await checkpoint?.call();
      }

      file.setPositionSync(position);
      final header = file.readSync(_blockSize);
      if (header.length < _blockSize) {
        // Целого блока нет: у настоящего архива такого хвоста не бывает, а в
        // самом начале это значит, что перед нами и не архив вовсе.
        if (position == 0) {
          throw FsError(archivePath, FsErrorKind.io);
        }
        break;
      }
      // Архив кончается двумя нулевыми блоками; хвост после них — заполнение.
      if (_isZeroBlock(header)) {
        break;
      }
      if (!_checksumMatches(header)) {
        throw FsError(archivePath, FsErrorKind.io);
      }

      final size = _parseSize(header, 124, 12);
      final type = _parseString(header, 156, 1);
      final contentOffset = position + _blockSize;
      position = contentOffset + _padded(size);

      // Служебные записи содержат не файл, а сведения о следующем за ними.
      if (type == _typeLongName || type == _typeLongLink) {
        final value = _readString(file, contentOffset, size);
        if (type == _typeLongName) {
          pendingName = value;
        } else {
          pendingLink = value;
        }
        continue;
      }
      if (type == _typePaxFile || type == _typePaxGlobal) {
        final records = _parsePax(_readString(file, contentOffset, size));
        pendingName = records['path'] ?? pendingName;
        pendingLink = records['linkpath'] ?? pendingLink;
        continue;
      }

      final name = pendingName ?? _fullName(header);
      final link = pendingLink ?? _parseString(header, 157, 100);
      pendingName = null;
      pendingLink = null;

      final segments = name.split('/').where((part) => part.isNotEmpty && part != '.').toList();
      if (segments.isEmpty) {
        continue;
      }

      final isDirectory = type == _typeDirectory || name.endsWith('/');
      final mode = _parseOctal(header, 100, 8);
      final modified = _parseTime(header);

      var parent = root;
      // Всё, кроме последней части, — каталоги; те, которых нет в архиве
      // отдельной записью, достраиваются здесь.
      for (final part in segments.take(segments.length - 1)) {
        parent = parent.children.putIfAbsent(part, () => TarEntry.directory(name: part));
      }

      final last = segments.last;
      if (isDirectory) {
        final existing = parent.children[last];
        // Настоящая запись каталога перебивает достроенную: у неё есть дата и
        // права, а у достроенной их нет.
        if (existing == null || existing.mode == 0) {
          final replacement = TarEntry.directory(name: last, modified: modified, mode: mode);
          replacement.children.addAll(existing?.children ?? const {});
          parent.children[last] = replacement;
        }
        continue;
      }

      parent.children[last] = TarEntry.file(
        name: last,
        size: size,
        offset: contentOffset,
        modified: modified,
        mode: mode,
        linkTarget: (type == _typeSymLink || type == _typeHardLink) && link.isNotEmpty ? link : null,
      );
    }

    // Пустой архив — это нулевые блоки и ничего больше, и он **не** ошибка:
    // `tar -cf empty.tar -T /dev/null` делает ровно такой. Отличить его от
    // файла, начинающегося с нулей, нечем — они побайтно одинаковы.
    return TarIndex(root);
  } finally {
    file.closeSync();
  }
}

/// Имя из заголовка вместе с приставкой формата ustar.
String _fullName(Uint8List header) {
  final name = _parseString(header, 0, 100);
  final prefix = _parseString(header, 345, 155);
  return prefix.isEmpty ? name : '$prefix/$name';
}

bool _isZeroBlock(Uint8List block) => block.every((byte) => byte == 0);

/// Контрольная сумма заголовка: сумма его байтов, где поле суммы считается
/// пробелами.
///
/// Единственный признак, по которому tar отличается от любого другого файла:
/// подписи у формата нет.
bool _checksumMatches(Uint8List header) {
  final declared = _parseOctal(header, 148, 8);
  var signed = 0;
  var unsigned = 0;
  for (var i = 0; i < _blockSize; i++) {
    final byte = i >= 148 && i < 156 ? 0x20 : header[i];
    unsigned += byte;
    signed += byte > 127 ? byte - 256 : byte;
  }
  // Старые архиваторы считали байты знаковыми — принимаем оба ответа.
  return declared == unsigned || declared == signed;
}

String _parseString(Uint8List header, int offset, int length) {
  final bytes = header.sublist(offset, offset + length);
  final end = bytes.indexOf(0);
  return utf8.decode(end < 0 ? bytes : bytes.sublist(0, end), allowMalformed: true).trim();
}

int _parseOctal(Uint8List header, int offset, int length) {
  final text = _parseString(header, offset, length).trim();
  if (text.isEmpty) {
    return 0;
  }
  return int.tryParse(text, radix: 8) ?? 0;
}

/// Размер записи: восьмеричным числом, а у больших файлов — двоичным.
///
/// Восьмёрка в двенадцати знаках кончается на 8 ГБ, поэтому для больших файлов
/// GNU и POSIX кладут число байтами, отмечая это старшим битом первого байта.
int _parseSize(Uint8List header, int offset, int length) {
  if (header[offset] & 0x80 == 0) {
    return _parseOctal(header, offset, length);
  }

  var value = header[offset] & 0x7f;
  for (var i = offset + 1; i < offset + length; i++) {
    value = (value << 8) | header[i];
  }
  return value;
}

DateTime? _parseTime(Uint8List header) {
  final seconds = _parseOctal(header, 136, 12);
  return seconds == 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

/// Сколько занимает содержимое вместе с добивкой до целого блока.
int _padded(int size) {
  final remainder = size % _blockSize;
  return remainder == 0 ? size : size + (_blockSize - remainder);
}

String _readString(RandomAccessFile file, int offset, int size) {
  file.setPositionSync(offset);
  final bytes = file.readSync(size);
  final end = bytes.indexOf(0);
  return utf8.decode(end < 0 ? bytes : bytes.sublist(0, end), allowMalformed: true).trim();
}

/// Записи PAX: «длина ключ=значение», по одной в строке.
Map<String, String> _parsePax(String content) {
  final records = <String, String>{};
  for (final line in const LineSplitter().convert(content)) {
    final space = line.indexOf(' ');
    final equals = line.indexOf('=');
    if (space < 0 || equals < space) {
      continue;
    }
    records[line.substring(space + 1, equals)] = line.substring(equals + 1);
  }
  return records;
}
