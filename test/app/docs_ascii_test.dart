import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Схемы в документации набраны только ASCII.
///
/// Почему это важно. Врезка набирается моноширинным шрифтом темы, и схема
/// держится на том, что все знаки одной ширины. Знака, которого в шрифте нет,
/// подстановка берёт из запасного — а у него ширина другая: Consolas даёт 11.00
/// на кегле 20, Menlo — 12.04. Буквы приходят из одного шрифта, рамки из
/// другого, и схема «плывёт» тем сильнее, чем она шире.
///
/// Поймать это глазами трудно: расхождение — девять процентов на знак, и видно
/// его только на длинной строке. Поэтому сторож, а не внимательность.
///
/// Запрещаем целыми диапазонами, а не списком знаков: в следующей схеме
/// захочется «ещё одну стрелочку», и список придётся дополнять задним числом.
void main() {
  /// Диапазоны, которых в моноширинном шрифте может не оказаться.
  const ranges = <({int from, int to, String what})>[
    (from: 0x2190, to: 0x21FF, what: 'стрелки'),
    (from: 0x2500, to: 0x257F, what: 'рамки'),
    (from: 0x2580, to: 0x259F, what: 'заливки'),
    (from: 0x25A0, to: 0x25FF, what: 'фигуры'),
    (from: 0x2600, to: 0x27BF, what: 'значки'),
  ];

  String? forbidden(String line) {
    for (final ch in line.runes) {
      for (final range in ranges) {
        if (ch >= range.from && ch <= range.to) {
          return '${String.fromCharCode(ch)} (${range.what}, U+${ch.toRadixString(16).toUpperCase()})';
        }
      }
    }

    return null;
  }

  List<File> docs() =>
      [
        ...Directory('docs').listSync(recursive: true).whereType<File>(),
        ...Directory('.').listSync().whereType<File>(),
      ].where((file) => file.path.endsWith('.md')).toList();

  test('во врезках документации только ASCII-графика', () {
    final broken = <String>[];

    for (final file in docs()) {
      var fenced = false;
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('```')) {
          fenced = !fenced;
          continue;
        }
        if (!fenced) {
          continue;
        }
        final found = forbidden(lines[i]);
        if (found != null) {
          broken.add('${file.path}:${i + 1}: $found');
        }
      }
    }

    expect(broken, isEmpty, reason: 'эти схемы поедут: знак придёт из запасного шрифта, а он шире');
  });

  test('сторож смотрит на настоящие файлы, а не в пустоту', () {
    // Иначе проверка молча пройдёт на пустом списке.
    expect(docs().length, greaterThan(20));
  });
}
