import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Начало файла из байтов и строк вперемешку.
Uint8List head(List<Object> parts) {
  final bytes = <int>[];
  for (final part in parts) {
    switch (part) {
      case String():
        bytes.addAll(part.codeUnits);
      case List<int>():
        bytes.addAll(part);
      case int():
        // Число — это столько нулей: место до подписи, стоящей со смещения.
        bytes.addAll(List.filled(part, 0));
      default:
        throw ArgumentError('Не байты и не строка: $part');
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  group('Сигнатуры', () {
    final cases = <String, (List<Object>, ContentType)>{
      'png': (
        [
          [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
        ],
        ContentTypeTable.png,
      ),
      'jpeg': (
        [
          [0xff, 0xd8, 0xff, 0xe0],
        ],
        ContentTypeTable.jpeg,
      ),
      'gif': (['GIF89a'], ContentTypeTable.gif),
      'pdf': (['%PDF-1.7'], ContentTypeTable.pdf),
      'postscript': (['%!PS-Adobe-3.0'], ContentTypeTable.postscript),
      'rtf': ([r'{\rtf1\ansi'], ContentTypeTable.rtf),
      'gzip': (
        [
          [0x1f, 0x8b, 0x08],
        ],
        ContentTypeTable.gzip,
      ),
      'bzip2': (['BZh9'], ContentTypeTable.bzip2),
      'xz': (
        [
          [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00],
        ],
        ContentTypeTable.xz,
      ),
      '7z': (
        [
          [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c],
        ],
        ContentTypeTable.sevenZip,
      ),
      'zstd': (
        [
          [0x28, 0xb5, 0x2f, 0xfd],
        ],
        ContentTypeTable.zstd,
      ),
      'rar': (
        [
          'Rar!',
          [0x1a, 0x07],
        ],
        ContentTypeTable.rar,
      ),
      'elf': (
        [
          [0x7f],
          'ELF',
        ],
        ContentTypeTable.elf,
      ),
      'wasm': (
        [
          [0x00],
          'asm',
        ],
        ContentTypeTable.wasm,
      ),
      'pe': (
        [
          'MZ',
          [0x90, 0x00],
        ],
        ContentTypeTable.pe,
      ),
      'sqlite': (
        [
          'SQLite format 3',
          [0x00],
        ],
        ContentTypeTable.sqlite,
      ),
      'plist': (['bplist00'], ContentTypeTable.plist),
      'icns': (['icns'], ContentTypeTable.icns),
      'ico': (
        [
          [0x00, 0x00, 0x01, 0x00],
        ],
        ContentTypeTable.ico,
      ),
      'ttf': (
        [
          [0x00, 0x01, 0x00, 0x00],
        ],
        ContentTypeTable.ttf,
      ),
      'otf': (['OTTO'], ContentTypeTable.otf),
      'woff': (['wOFF'], ContentTypeTable.woff),
      'woff2': (['wOF2'], ContentTypeTable.woff2),
      'ogg': (['OggS'], ContentTypeTable.ogg),
      'flac': (['fLaC'], ContentTypeTable.flac),
      'midi': (['MThd'], ContentTypeTable.midi),
      'mp3 по ID3': (
        [
          'ID3',
          [0x04],
        ],
        ContentTypeTable.mp3,
      ),
      'mp3 по кадру': (
        [
          [0xff, 0xfb, 0x90],
        ],
        ContentTypeTable.mp3,
      ),
      'matroska': (
        [
          [0x1a, 0x45, 0xdf, 0xa3],
        ],
        ContentTypeTable.matroska,
      ),
      'tiff LE': (
        [
          [0x49, 0x49, 0x2a, 0x00],
        ],
        ContentTypeTable.tiff,
      ),
      'tiff BE': (
        [
          [0x4d, 0x4d, 0x00, 0x2a],
        ],
        ContentTypeTable.tiff,
      ),
      'bmp': (['BM', 0x40], ContentTypeTable.bmp),
      'скрипт по #!': (['#!/bin/sh\n'], ContentTypeTable.script),
      'mach-o 32': (
        [
          [0xfe, 0xed, 0xfa, 0xce],
        ],
        ContentTypeTable.machO,
      ),
      'mach-o 64': (
        [
          [0xfe, 0xed, 0xfa, 0xcf],
        ],
        ContentTypeTable.machO,
      ),
      'mach-o LE': (
        [
          [0xcf, 0xfa, 0xed, 0xfe],
        ],
        ContentTypeTable.machO,
      ),
      'mach-o fat наоборот': (
        [
          [0xbe, 0xba, 0xfe, 0xca],
        ],
        ContentTypeTable.machOFat,
      ),
      'mach-o fat 64': (
        [
          [0xca, 0xfe, 0xba, 0xbf],
        ],
        ContentTypeTable.machOFat,
      ),
      'mp4': ([4, 'ftypisom'], ContentTypeTable.mp4),
      'mov': ([4, 'ftypqt  '], ContentTypeTable.mov),
      'ar': (['!<arch>\n', 'file.o/  '], ContentTypeTable.ar),
      'deb': (['!<arch>\n', 'debian-binary'], ContentTypeTable.deb),
    };

    cases.forEach((name, data) {
      test(name, () => expect(ContentTypeTable.of(head(data.$1)), data.$2));
    });

    test('dicom узнаётся со смещения 128', () {
      expect(ContentTypeTable.of(head([128, 'DICM'])), ContentTypeTable.dicom);
    });

    test('tar узнаётся со смещения 257', () {
      expect(ContentTypeTable.of(head([257, 'ustar'])), ContentTypeTable.tar);
    });

    test('файл короче 262 байт tar-ом быть не может', () {
      expect(ContentTypeTable.of(head([200, 'ustar'])), isNot(ContentTypeTable.tar));
    });
  });

  group('Обманки', () {
    test('пустой zip начинается с записи конца каталога, а не с локального заголовка', () {
      expect(
        ContentTypeTable.of(
          head([
            [0x50, 0x4b, 0x05, 0x06],
            18,
          ]),
        ),
        ContentTypeTable.zip,
      );
    });

    test('zip разделённый — тоже zip', () {
      expect(
        ContentTypeTable.of(
          head([
            [0x50, 0x4b, 0x07, 0x08],
          ]),
        ),
        ContentTypeTable.zip,
      );
    });

    test('обычный zip', () {
      expect(
        ContentTypeTable.of(
          head([
            [0x50, 0x4b, 0x03, 0x04],
          ]),
        ),
        ContentTypeTable.zip,
      );
    });

    test('CA FE BA BE с версией — Java-класс', () {
      // minor 0, major 52 — Java 8.
      expect(
        ContentTypeTable.of(
          head([
            [0xca, 0xfe, 0xba, 0xbe, 0x00, 0x00, 0x00, 0x34],
          ]),
        ),
        ContentTypeTable.javaClass,
      );
    });

    test('CA FE BA BE с числом архитектур — толстый Mach-O', () {
      expect(
        ContentTypeTable.of(
          head([
            [0xca, 0xfe, 0xba, 0xbe, 0x00, 0x00, 0x00, 0x02],
          ]),
        ),
        ContentTypeTable.machOFat,
      );
    });

    test('CA FE BA BE, не похожее ни на то ни на другое, — двоичное', () {
      expect(
        ContentTypeTable.of(
          head([
            [0xca, 0xfe, 0xba, 0xbe, 0x7f, 0x1f, 0x00, 0x02],
          ]),
        ),
        ContentTypeTable.binary,
      );
    });

    test('RIFF сам по себе ничего не значит', () {
      expect(ContentTypeTable.of(head(['RIFF', 4, 'CDDA'])), ContentTypeTable.binary);
    });

    test('RIFF + WEBP — картинка', () {
      expect(ContentTypeTable.of(head(['RIFF', 4, 'WEBPVP8 '])), ContentTypeTable.webp);
    });

    test('RIFF + WAVE — звук', () {
      expect(ContentTypeTable.of(head(['RIFF', 4, 'WAVEfmt '])), ContentTypeTable.wav);
    });

    test('RIFF + AVI — видео', () {
      expect(ContentTypeTable.of(head(['RIFF', 4, 'AVI LIST'])), ContentTypeTable.avi);
    });
  });

  group('Текст и двоичное', () {
    test('простой текст', () {
      expect(ContentTypeTable.of(head(['hello, world\n'])), ContentTypeTable.text);
    });

    test('UTF-8 без метки', () {
      expect(ContentTypeTable.of(Uint8List.fromList(utf8.encode('привет'))), ContentTypeTable.text);
    });

    test('UTF-8 с меткой', () {
      expect(
        ContentTypeTable.of(
          head([
            [0xef, 0xbb, 0xbf],
            'hello',
          ]),
        ),
        ContentTypeTable.text,
      );
    });

    test('UTF-16 с меткой — текст', () {
      expect(
        ContentTypeTable.of(
          head([
            [0xff, 0xfe, 0x41, 0x00, 0x42, 0x00],
          ]),
        ),
        ContentTypeTable.text,
      );
      expect(
        ContentTypeTable.of(
          head([
            [0xfe, 0xff, 0x00, 0x41, 0x00, 0x42],
          ]),
        ),
        ContentTypeTable.text,
      );
    });

    test('UTF-16 без метки — двоичное', () {
      expect(
        ContentTypeTable.of(
          head([
            [0x41, 0x00, 0x42, 0x00, 0x43, 0x00],
          ]),
        ),
        ContentTypeTable.binary,
      );
    });

    test('нулевой байт посреди текста — двоичное', () {
      expect(
        ContentTypeTable.of(
          head([
            'text',
            [0x00],
            'more',
          ]),
        ),
        ContentTypeTable.binary,
      );
    });

    test('символ, оборванный границей чтения, — всё ещё текст', () {
      // «привет» без последнего байта: обрывок не повод объявить файл двоичным.
      final full = utf8.encode('привет');
      expect(ContentTypeTable.of(Uint8List.fromList(full.sublist(0, full.length - 1))), ContentTypeTable.text);
    });

    test('svg — картинка, а не просто текст', () {
      expect(
        ContentTypeTable.of(head(['<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>'])),
        ContentTypeTable.svg,
      );
    });

    test('пустой файл — двоичное, и это ответ', () {
      expect(ContentTypeTable.of(Uint8List(0)), ContentTypeTable.binary);
    });

    test('случайные байты — двоичное', () {
      expect(
        ContentTypeTable.of(
          head([
            [0x8f, 0x92, 0xa1, 0xff, 0xfe, 0x01],
          ]),
        ),
        ContentTypeTable.binary,
      );
    });
  });

  group('Порядок таблицы', () {
    test('короткая сигнатура не стоит раньше длинной, которая с неё начинается', () {
      final signatures = ContentTypeTable.signatures;
      for (var i = 0; i < signatures.length; i++) {
        for (var j = i + 1; j < signatures.length; j++) {
          final earlier = signatures[i];
          final later = signatures[j];
          if (earlier.at != later.at || earlier.bytes.length >= later.bytes.length) {
            continue;
          }
          final prefix = later.bytes.sublist(0, earlier.bytes.length);
          expect(
            prefix,
            isNot(earlier.bytes),
            reason:
                'Сигнатура ${earlier.type.id} (${earlier.bytes.length} б) стоит раньше '
                '${later.type.id} (${later.bytes.length} б) и съест её',
          );
        }
      }
    });

    test('имена типов не повторяются', () {
      final ids = ContentTypeTable.all.map((type) => type.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
