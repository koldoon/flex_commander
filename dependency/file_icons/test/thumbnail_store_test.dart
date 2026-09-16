import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Система, которая отвечает по команде теста, и видно, кого она спрашивала.
class FakeThumbnails implements SystemThumbnails {
  final List<String> asked = [];

  /// Кто ещё не ответил: тест держит их, пока считает одновременных.
  final List<Completer<Uint8List?>> waiting = [];

  /// Сколько байтов в ответе; 0 — миниатюры нет.
  int size = 64;

  /// Отвечать сразу или ждать команды.
  bool holds = false;

  int get running => waiting.length;

  @override
  Future<Uint8List?> forPath(String path, {required int pixels}) {
    asked.add('$path@$pixels');
    final answer = size == 0 ? null : Uint8List(size);
    if (!holds) {
      return Future.value(answer);
    }
    final gate = Completer<Uint8List?>();
    waiting.add(gate);
    return gate.future;
  }

  /// Отпустить всех, кто ждёт.
  void release() {
    final held = [...waiting];
    waiting.clear();
    for (final gate in held) {
      gate.complete(size == 0 ? null : Uint8List(size));
    }
  }
}

FileEntry file(String name, {String realPath = '/tmp/x', DateTime? modified, EntryKind kind = EntryKind.file}) =>
    FileEntry(name: name, kind: kind, path: 'fs:/tmp/$name', realPath: realPath, size: 16, modified: modified);

void main() {
  late FakeThumbnails system;

  setUp(() => system = FakeThumbnails());

  ThumbnailStore storeOf({int concurrency = ThumbnailStore.defaultConcurrency, int budget = 1 << 20}) =>
      ThumbnailStore(thumbnails: system, concurrency: concurrency, budget: budget);

  test('спрашивают только о местном файле', () {
    final store = storeOf();

    expect(store.wants(file('a.jpg'), 128), isTrue);
    expect(store.wants(file('a.jpg', realPath: ''), 128), isFalse, reason: 'системе нужен путь на диске');
    expect(store.wants(file('src', kind: EntryKind.directory), 128), isFalse, reason: 'у каталога содержимого нет');
  });

  test('одновременно идёт не больше четырёх', () async {
    final store = storeOf();
    system.holds = true;

    for (var at = 0; at < 10; at++) {
      unawaited(store.ask(file('$at.jpg', realPath: '/tmp/$at.jpg'), 128));
    }
    await Future<void>.delayed(Duration.zero);

    expect(system.running, ThumbnailStore.defaultConcurrency, reason: 'пятый ждёт своей очереди');

    system.release();
    await Future<void>.delayed(Duration.zero);
    expect(system.asked.length, greaterThan(ThumbnailStore.defaultConcurrency), reason: 'очередь пошла дальше');
  });

  test('уехавшая с экрана плитка вопроса не задаёт', () async {
    final store = storeOf(concurrency: 1);
    system.holds = true;

    unawaited(store.ask(file('first.jpg', realPath: '/tmp/first.jpg'), 128));
    // Второй встал в очередь и уехал, пока первый шёл.
    final gone = store.ask(file('gone.jpg', realPath: '/tmp/gone.jpg'), 128, stillWanted: () => false);

    system.release();
    await gone;

    expect(system.asked, ['/tmp/first.jpg@128'], reason: 'о уехавшем не спрашивали');
    // И это не отказ: файл не спрашивали вовсе, значит спросят, когда вернётся.
    expect(store.wants(file('gone.jpg', realPath: '/tmp/gone.jpg'), 128), isTrue);
  });

  test('два спрашивающих об одном — один вопрос', () async {
    final store = storeOf();
    final entry = file('one.jpg', realPath: '/tmp/one.jpg');

    await Future.wait([store.ask(entry, 128), store.ask(entry, 128)]);

    expect(system.asked, ['/tmp/one.jpg@128']);
  });

  test('приехавшее помнится и больше не спрашивается', () async {
    final store = storeOf();
    final entry = file('one.jpg', realPath: '/tmp/one.jpg');

    await store.ask(entry, 128);

    expect(store.known(entry, 128), isNotNull);
    expect(store.wants(entry, 128), isFalse);
  });

  test('отказ помнится: второй раз в этот сеанс не спрашиваем', () async {
    final store = storeOf();
    system.size = 0;
    final entry = file('doc.7z', realPath: '/tmp/doc.7z');

    await store.ask(entry, 128);

    expect(store.known(entry, 128), isNull);
    expect(store.wants(entry, 128), isFalse, reason: 'у архива миниатюры нет, и это ответ');
  });

  test('правка файла — другая картинка', () async {
    final store = storeOf();
    final before = file('one.jpg', realPath: '/tmp/one.jpg', modified: DateTime(2026));
    final after = file('one.jpg', realPath: '/tmp/one.jpg', modified: DateTime(2026, 2));

    await store.ask(before, 128);

    expect(store.known(after, 128), isNull, reason: 'вчерашняя картинка — худший вид ошибки: правдоподобный');
    expect(store.wants(after, 128), isTrue);
  });

  test('размер — часть вопроса', () async {
    final store = storeOf();
    final entry = file('one.jpg', realPath: '/tmp/one.jpg');

    await store.ask(entry, 128);

    expect(store.known(entry, 256), isNull);
    expect(store.wants(entry, 256), isTrue);
  });

  test('кеш считается байтами, а не записями', () async {
    // Бюджета хватает на две картинки из трёх.
    final store = storeOf(budget: 150);
    system.size = 64;

    final first = file('1.jpg', realPath: '/tmp/1.jpg');
    final second = file('2.jpg', realPath: '/tmp/2.jpg');
    final third = file('3.jpg', realPath: '/tmp/3.jpg');
    await store.ask(first, 128);
    await store.ask(second, 128);
    await store.ask(third, 128);

    expect(store.bytes, lessThanOrEqualTo(150));
    expect(store.known(third, 128), isNotNull, reason: 'последнее спрошенное остаётся');
    expect(store.known(first, 128), isNull, reason: 'вытеснено по давности');
  });
}
