import 'dart:io';

import 'package:archive/archive.dart';

import 'package:fc_api/fc_api.dart';

/// Запись оглавления архива: то, что о ней известно без распаковки.
///
/// Каталоги в zip — не обязательные записи, а соглашение об именах: `a/b.txt`
/// может лежать в архиве, где никакого `a/` нет вовсе. Поэтому каталоги здесь
/// достраиваются по путям, и у достроенного нет ни даты, ни прав.
class ZipEntry {
  ZipEntry({required this.name, required this.isDirectory, this.entryName = '', this.size = 0, this.modified})
    : mode = 0;

  ZipEntry.file({required this.name, required this.entryName, required this.size, this.modified, this.mode = 0})
    : isDirectory = false;

  ZipEntry.directory({required this.name, this.entryName = '', this.modified, this.mode = 0})
    : isDirectory = true,
      size = 0;

  /// Имя внутри родительского каталога.
  final String name;

  /// Полное имя записи в архиве — по нему запись и читается.
  final String entryName;

  final bool isDirectory;
  final int size;
  final DateTime? modified;

  /// Права доступа из архива; 0 — их там не было.
  final int mode;

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
