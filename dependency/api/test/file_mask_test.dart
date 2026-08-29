import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Маска имён: два знака подстановки, список через `;` и исключения.
void main() {
  bool matches(String patterns, String name) => FileMask.parse(patterns).matches(name);

  test('звёздочка — сколько угодно, вопрос — ровно один', () {
    expect(matches('*.dart', 'main.dart'), isTrue);
    expect(matches('*.dart', 'main.dart.bak'), isFalse);
    expect(matches('?.dart', 'a.dart'), isTrue);
    expect(matches('?.dart', 'ab.dart'), isFalse);
  });

  test('несколько образцов через точку с запятой', () {
    expect(matches('*.dart;*.md', 'readme.md'), isTrue);
    expect(matches('*.dart;*.md', 'main.dart'), isTrue);
    expect(matches('*.dart;*.md', 'photo.png'), isFalse);
  });

  test('регистр не важен', () {
    expect(matches('*.PNG', 'photo.png'), isTrue);
    expect(matches('*.png', 'PHOTO.PNG'), isTrue);
  });

  test('исключения применяются последними — в любом порядке', () {
    // «Всё, кроме .bak» читается одинаково, как ни переставь.
    expect(matches('*;!*.bak', 'main.dart'), isTrue);
    expect(matches('*;!*.bak', 'main.bak'), isFalse);
    expect(matches('!*.bak;*', 'main.bak'), isFalse);
    expect(matches('!*.bak;*', 'main.dart'), isTrue);
  });

  test('одни исключения не совпадают ни с чем: разрешать нечего', () {
    expect(matches('!*.bak', 'main.dart'), isFalse);
  });

  test('пустая маска не совпадает ни с чем, звёздочка — со всем', () {
    expect(matches('', 'main.dart'), isFalse);
    expect(matches('   ', 'main.dart'), isFalse);
    expect(matches('*', 'main.dart'), isTrue);
    expect(matches('*', '.gitignore'), isTrue);
    expect(FileMask.parse('').isEmpty, isTrue);
  });

  test('маска смотрит на имя целиком, а не на расширение в нашем смысле', () {
    // У `.gitignore` расширения нет (`FileNode.extension` пусто), но маска
    // работает с именем — и совпадает.
    expect(matches('*.gitignore', '.gitignore'), isTrue);
    // Каталог `src.d` — такое же имя, как файл: маска их не различает.
    expect(matches('*.d', 'src.d'), isTrue);
  });

  test('пробелы вокруг образцов не мешают', () {
    expect(matches(' *.dart ; *.md ', 'readme.md'), isTrue);
  });

  test('точки и прочие знаки не считаются выражением', () {
    expect(matches('a.b', 'axb'), isFalse, reason: 'точка — это точка, а не «любой символ»');
    expect(matches(r'file(1).txt', 'file(1).txt'), isTrue);
  });
}
