import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Приёмник, которому есть разница между «готово» и «брось»
/// (`AbortableSink`, `docs/spec/s3.md`, §11).
///
/// Многочастная загрузка S3 на `close()` собирает объект из принятого. Движок
/// после ошибки обязан звать `abort()`, а не `close()` — иначе обрубок стал бы
/// настоящим объектом.
void main() {
  const engine = TreeTransferEngine();

  late _RecordingProvider box;

  setUp(() => box = _RecordingProvider([FakeEntry.directory('/box')]));

  Future<DirectoryNode> target() async => (await box.resolvePath().run('/box'))! as DirectoryNode;

  Future<List<FsNode>> sources(InMemoryContentProvider disk) async {
    final dir = (await disk.resolvePath().run('/home'))! as DirectoryNode;
    return (await disk.getDirectoryListing().run(ListingParams(dir))).where((node) => node is! ParentDirNode).toList();
  }

  test('дописали — приёмник закрыт, а не брошен', () async {
    final disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.bin', content: [1, 2, 3]),
    ]);

    await engine.copy().run(TransferParams(await sources(disk), await target()));

    expect(box.events, ['close']);
  });

  test('источник сломался посреди файла — приёмник брошен, а не закрыт', () async {
    final disk = _BrokenSource([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.bin', content: List.filled(64, 1)),
    ]);

    // Ошибку движок копит и отчитывается о ней сам — здесь важно, что сделано с
    // приёмником.
    await _swallow(engine.copy().run(TransferParams(await sources(disk), await target())));

    expect(box.events, ['abort'], reason: 'close() собрал бы из обрубка настоящий объект');
  });

  test('обычный приёмник после ошибки закрывается, как и раньше', () async {
    final plain = InMemoryContentProvider([FakeEntry.directory('/box')]);
    final disk = _BrokenSource([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.bin', content: List.filled(64, 1)),
    ]);
    final box = (await plain.resolvePath().run('/box'))! as DirectoryNode;

    await _swallow(engine.copy().run(TransferParams(await sources(disk), box)));

    // Недописанное убрано, как было всегда.
    expect(await plain.resolvePath().run('/box/a.bin'), isNull);
  });

  test('abandonSink глотает ошибку уборки', () async {
    await expectLater(abandonSink(_FailingAbortSink()), completes);
  });
}

/// Дождаться работы, как бы она ни кончилась.
Future<void> _swallow(Future<void> work) async {
  try {
    await work;
  } on Object {
    // Как кончилась работа, здесь неважно.
  }
}

/// Приёмник, чьи `close` и `abort` записываются по порядку.
class _RecordingProvider extends InMemoryContentProvider {
  _RecordingProvider(super.entries);

  final List<String> events = [];

  @override
  Future<StreamSink<List<int>>> openWrite(DirectoryNode parent, String name, {int? length}) async =>
      _RecordingSink(await super.openWrite(parent, name, length: length), events);
}

class _RecordingSink implements StreamSink<List<int>>, AbortableSink {
  _RecordingSink(this._inner, this._events);

  final StreamSink<List<int>> _inner;
  final List<String> _events;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future<void> close() {
    _events.add('close');
    return _inner.close();
  }

  @override
  Future<void> abort() async {
    _events.add('abort');
  }

  @override
  Future<void> get done => _inner.done;
}

/// Источник, чьё чтение ломается после первого куска.
class _BrokenSource extends InMemoryContentProvider {
  _BrokenSource(super.entries);

  @override
  Future<Stream<List<int>>> openRead(FsNode node, {int offset = 0}) async {
    final controller = StreamController<List<int>>();
    controller
      ..add([1, 2, 3])
      ..addError(FsError(node.pathString, FsErrorKind.io))
      ..close();
    return controller.stream;
  }
}

class _FailingAbortSink implements StreamSink<List<int>>, AbortableSink {
  @override
  Future<void> abort() => Future.error(StateError('уборка не удалась'));

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
