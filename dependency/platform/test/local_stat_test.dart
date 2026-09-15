import 'dart:io';

import 'package:fc_platform/fc_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Свой `stat(2)`: то же, что рассказывает `dart:io`, плюс числа владельца
/// (`docs/spec/owner-columns.md`, §3).
///
/// Сверка с `FileStat` — единственное, что отделяет верную раскладку структуры
/// от порчи чужой памяти: поля читаются по смещениям, и промах виден только так.
void main() {
  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fc_stat');
    file = File('${temp.path}/notes.txt')..writeAsStringSync('двадцать четыре байта');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('читает то же, что dart:io', () {
    final stat = LocalStat.instance;
    if (stat == null) {
      return; // Не macOS: своего вызова здесь нет, работает FileStat.
    }

    final theirs = FileStat.statSync(file.path);
    final ours = stat.readOf(file.path);

    expect(ours, isNotNull);
    expect(ours!.mode, theirs.mode & 0xFFFF, reason: 'режим доступа');
    expect(ours.size, theirs.size, reason: 'размер');
    // До секунды: наносекунды мы не читаем, а `FileStat` округляет по-своему.
    expect(ours.modified.difference(theirs.modified).inSeconds.abs(), lessThanOrEqualTo(1));
    expect(ours.accessed.difference(theirs.accessed).inSeconds.abs(), lessThanOrEqualTo(1));
    expect(ours.changed.difference(theirs.changed).inSeconds.abs(), lessThanOrEqualTo(1));
  });

  test('числа владельца — те же, что у id', () {
    final stat = LocalStat.instance;
    if (stat == null) {
      return;
    }

    final ours = stat.readOf(file.path)!;
    expect('${ours.uid}', Process.runSync('id', ['-u']).stdout.toString().trim());
    expect('${ours.gid}', Process.runSync('id', ['-g']).stdout.toString().trim());
  });

  test('каталог читается так же, как файл', () {
    final stat = LocalStat.instance;
    if (stat == null) {
      return;
    }

    final ours = stat.readOf(temp.path);

    expect(ours, isNotNull);
    expect(ours!.mode & 0x4000, 0x4000, reason: 'S_IFDIR — это каталог');
  });

  test('чего нет — про то и не рассказывает', () {
    final stat = LocalStat.instance;
    if (stat == null) {
      return;
    }

    expect(stat.readOf('${temp.path}/такого-файла-нет'), isNull);
  });
}
