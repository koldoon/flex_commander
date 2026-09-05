import 'dart:io';

import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('«~» разворачивается в домашний каталог', () {
    final pictures = PictureFiles(home: '/Users/koldoon');

    expect(pictures.expand('~/icons/dart.png'), '/Users/koldoon/icons/dart.png');
    expect(pictures.expand('~'), '/Users/koldoon');
    expect(pictures.expand('/tmp/dart.png'), '/tmp/dart.png');
    // `~foo` — это не «домашний каталог», а имя, начинающееся с тильды.
    expect(pictures.expand('~foo/dart.png'), '~foo/dart.png');
  });

  test('без домашнего каталога тильда остаётся как есть', () {
    expect(PictureFiles(home: '').expand('~/dart.png'), '~/dart.png');
  });

  test('файл есть — есть чем рисовать; нет — нечем', () {
    final directory = Directory.systemTemp.createTempSync('fc_icons');
    addTearDown(() => directory.deleteSync(recursive: true));

    final picture = File('${directory.path}/dart.png')..writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    final pictures = PictureFiles(home: directory.path);

    expect(pictures.of(picture.path), isNotNull);
    expect(pictures.of('~/dart.png'), isNotNull, reason: 'тот же файл через тильду');
    expect(pictures.of('${directory.path}/missing.png'), isNull);
  });

  test('ответ запоминается — в том числе отрицательный', () {
    final directory = Directory.systemTemp.createTempSync('fc_icons');
    addTearDown(() => directory.deleteSync(recursive: true));

    final path = '${directory.path}/later.png';
    final pictures = PictureFiles();
    expect(pictures.of(path), isNull);

    File(path).writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    // Появившийся файл подхватится со следующего запуска: стучаться на диск на
    // каждую перерисовку строки нельзя.
    expect(pictures.of(path), isNull);
  });
}
