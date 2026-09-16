@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Слежение за каталогом на **настоящей** файловой системе
/// (`docs/spec/directory-watch.md`, §2).
///
/// Подставкой это не проверить: весь этап держится на повадках системы —
/// сколько событий она пришлёт, придут ли события старше подписки, что будет с
/// потоком, когда каталог исчезнет. Подставка подтвердила бы любую догадку.
///
/// Свой предел времени: несработавшая подписка **молчит**, и без него прогон
/// выглядел бы зависшим, а не красным.
void main() {
  late Directory temp;
  late String root;
  late LocalTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_watch');
    // На macOS временный каталог лежит за символической ссылкой
    // (`/var` → `/private/var`), а следим мы по разрешённому пути.
    root = await temp.resolveSymbolicLinks();
    provider = LocalTreeProvider(homePath: root, readInIsolate: false);
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  Future<DirectoryNode> dirAt(String path) async => await provider.resolvePath().run(path) as DirectoryNode;

  /// Ждёт, пока условие сбудется; шагом, а не сном: задержка события живая
  /// (30–115 мс живьём), и постоянный сон врёт в обе стороны.
  Future<bool> waitFor(bool Function() done, {int tries = 300}) async {
    for (var at = 0; at < tries; at++) {
      if (done()) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return done();
  }

  test('создание, удаление и переименование доходят до потока', () async {
    var events = 0;
    final watch = provider.watchDirectory(await dirAt(root)).listen((_) => events++);
    addTearDown(watch.cancel);
    // Даём подписке подняться: события, случившиеся раньше, система тоже
    // присылает, но ждать их — не то же самое, что проверять свои.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final file = File(p.join(root, 'one.txt'));
    var seen = events;
    file.writeAsStringSync('hello');
    expect(await waitFor(() => events > seen), isTrue, reason: 'создание');

    seen = events;
    file.renameSync(p.join(root, 'two.txt'));
    expect(await waitFor(() => events > seen), isTrue, reason: 'переименование');

    seen = events;
    File(p.join(root, 'two.txt')).deleteSync();
    expect(await waitFor(() => events > seen), isTrue, reason: 'удаление');
  });

  test('одно действие присылает не одно событие — накопление не роскошь', () async {
    var events = 0;
    final watch = provider.watchDirectory(await dirAt(root)).listen((_) => events++);
    addTearDown(watch.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    for (var at = 0; at < 20; at++) {
      File(p.join(root, 'f$at.txt')).writeAsStringSync('$at');
    }
    await waitFor(() => events >= 20);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(events, greaterThan(20), reason: 'двадцать файлов — больше двадцати событий');
  });

  test('каталог исчез — поток закрылся', () async {
    final inner = Directory(p.join(root, 'sub'))..createSync();
    var closed = false;
    final watch = provider.watchDirectory(await dirAt(inner.path)).listen((_) {}, onDone: () => closed = true);
    addTearDown(watch.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    inner.deleteSync(recursive: true);

    expect(await waitFor(() => closed), isTrue, reason: 'следить больше не за чем — и поток об этом говорит');
  });

  test('каталога нет — поток пустой, а не ошибка', () async {
    // Каталога нет вовсе: узел берём у существующего и подменяем путь — так
    // это и случается живьём, когда каталог исчез между разбором и подпиской.
    Directory(p.join(root, 'nowhere')).createSync();
    final gone = await dirAt(p.join(root, 'nowhere'));
    Directory(p.join(root, 'nowhere')).deleteSync();

    var events = 0;
    var closed = false;
    final watch = provider.watchDirectory(gone).listen((_) => events++, onDone: () => closed = true);
    addTearDown(watch.cancel);

    expect(await waitFor(() => closed), isTrue);
    expect(events, 0, reason: 'следить здесь нечем — это не отказ');
  });
}
