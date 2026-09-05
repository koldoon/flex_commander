import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_content_types/fc_content_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// Содержимое, за которым видно, читали его или нет.
class FakeContent implements Content {
  FakeContent(this.bytes, {this.gate, this.fails = false});

  final List<int> bytes;

  /// Пока не открыт, чтение стоит: так проверяется пул.
  final Completer<void>? gate;

  /// Читать не дадут — прав не хватило, источник отвалился.
  final bool fails;

  /// Сколько раз за байтами приходили.
  int reads = 0;

  @override
  int get length => bytes.length;

  @override
  Stream<List<int>> read({int offset = 0}) async* {
    reads++;
    if (gate != null) {
      await gate!.future;
    }
    if (fails) {
      throw const FsError('fs:/tmp/locked', FsErrorKind.permissionDenied);
    }
    yield bytes.sublist(offset);
  }
}

FileEntry file(String name, {int size = 16, DateTime? modified}) => FileEntry(
  name: name,
  kind: EntryKind.file,
  path: 'fs:/tmp/$name',
  size: size,
  modified: modified ?? DateTime(2026, 9, 5),
);

final List<int> pngBytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13];

void main() {
  ContentTypeService serviceWith({int concurrency = 4, int cacheLimit = ContentTypeService.defaultCacheLimit}) =>
      ContentTypeService(concurrency: () => concurrency, cacheLimit: cacheLimit);

  test('пока не спросили, тип неизвестен', () {
    expect(serviceWith().known(file('a.png')), isNull);
  });

  test('прочитанный тип запоминается', () async {
    final service = serviceWith();
    final entry = file('a.png');
    final content = FakeContent(pngBytes);

    expect(await service.detect(entry, () => content), ContentTypeTable.png);
    expect(service.known(entry), ContentTypeTable.png);
    expect(content.reads, 1);

    // Второй вопрос — из кэша, файл не открывается.
    expect(await service.detect(entry, () => content), ContentTypeTable.png);
    expect(content.reads, 1);
  });

  test('второй вопрос до ответа не открывает файл второй раз', () async {
    final service = serviceWith();
    final entry = file('a.png');
    final gate = Completer<void>();
    final content = FakeContent(pngBytes, gate: gate);

    final first = service.detect(entry, () => content);
    final second = service.detect(entry, () => content);
    gate.complete();

    expect(await first, ContentTypeTable.png);
    expect(await second, ContentTypeTable.png);
    expect(content.reads, 1);
  });

  test('тот же путь с другим размером читается заново', () async {
    final service = serviceWith();
    final before = FakeContent(pngBytes);
    final after = FakeContent([0x25, 0x50, 0x44, 0x46]);

    expect(await service.detect(file('a.dat', size: 16), () => before), ContentTypeTable.png);
    expect(await service.detect(file('a.dat', size: 32), () => after), ContentTypeTable.pdf);
    expect(after.reads, 1);
  });

  test('тот же путь с другой датой читается заново', () async {
    final service = serviceWith();
    final before = FakeContent(pngBytes);
    final after = FakeContent([0x25, 0x50, 0x44, 0x46]);

    expect(await service.detect(file('a.dat', modified: DateTime(2026, 1, 1)), () => before), ContentTypeTable.png);
    expect(await service.detect(file('a.dat', modified: DateTime(2026, 2, 2)), () => after), ContentTypeTable.pdf);
    expect(after.reads, 1);
  });

  test('пустой файл не читается вовсе', () async {
    final service = serviceWith();
    final entry = file('empty', size: 0);
    final content = FakeContent(const []);

    expect(await service.detect(entry, () => content), ContentTypeTable.binary);
    expect(content.reads, 0);
    expect(service.known(entry), ContentTypeTable.binary);
  });

  test('каталог и ссылка не спрашиваются', () async {
    final service = serviceWith();
    final content = FakeContent(pngBytes);

    for (final kind in [EntryKind.directory, EntryKind.link, EntryKind.parent]) {
      final entry = FileEntry(name: 'thing', kind: kind, path: 'fs:/tmp/thing', size: 16);
      expect(await service.detect(entry, () => content), isNull);
    }
    expect(content.reads, 0);
  });

  test('строка, уехавшая с экрана, не читается', () async {
    final service = serviceWith();
    final entry = file('a.png');
    final content = FakeContent(pngBytes);

    expect(await service.detect(entry, () => content, stillWanted: () => false), isNull);
    expect(content.reads, 0);
    // И ничего не запомнилось: спросят снова — прочитаем.
    expect(service.known(entry), isNull);
    expect(await service.detect(entry, () => content), ContentTypeTable.png);
  });

  test('нечитаемый файл не роняет и второй раз не пробуется', () async {
    final service = serviceWith();
    final entry = file('locked');
    final content = FakeContent(pngBytes, fails: true);

    expect(await service.detect(entry, () => content), isNull);
    expect(service.known(entry), isNull);

    expect(await service.detect(entry, () => content), isNull);
    expect(content.reads, 1);
  });

  test('пул не пускает читать больше, чем позволено', () async {
    final service = serviceWith(concurrency: 2);
    final gates = [for (var i = 0; i < 5; i++) Completer<void>()];
    final contents = [for (var i = 0; i < 5; i++) FakeContent(pngBytes, gate: gates[i])];

    final answers = [for (var i = 0; i < 5; i++) service.detect(file('file$i.dat'), () => contents[i])];
    await pumpEventQueue();

    expect(contents.where((content) => content.reads > 0).length, 2);

    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait(answers);
    expect(contents.every((content) => content.reads == 1), isTrue);
  });

  test('кэш вытесняет самое давнее', () async {
    final service = serviceWith(cacheLimit: 2);
    final first = file('one.png');

    await service.detect(first, () => FakeContent(pngBytes));
    await service.detect(file('two.png'), () => FakeContent(pngBytes));
    expect(service.known(first), ContentTypeTable.png);

    await service.detect(file('three.png'), () => FakeContent(pngBytes));
    expect(service.known(first), isNull);
  });
}
