import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/directory_watch.dart';
import 'package:flutter_test/flutter_test.dart';

/// Слой слежения: подписка, накопление, смерть потока
/// (`docs/spec/directory-watch.md`, §5).
void main() {
  const quiet = Duration(milliseconds: 30);

  late _WatchedProvider source;
  late int refreshes;
  late bool enabled;
  late DirectoryWatch watch;

  setUp(() {
    source = _WatchedProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/one.txt', size: 1),
    ]);
    refreshes = 0;
    enabled = true;
    watch = DirectoryWatch(refresh: () async => refreshes++, enabled: () => enabled, delay: () => quiet);
  });

  tearDown(() => watch.dispose());

  Future<DirectoryNode> dirAt(String path) async => await source.resolvePath().run(path) as DirectoryNode;

  /// Подождать конца окна накопления.
  Future<void> settle() => Future<void>.delayed(quiet * 3);

  test('событие перечитывает каталог', () async {
    watch.follow(await dirAt('/home'));
    expect(watch.watching, isTrue);

    source.touch('/home');
    await settle();

    expect(refreshes, 1);
  });

  test('пачка событий стоит одного перечитывания', () async {
    watch.follow(await dirAt('/home'));

    for (var at = 0; at < 50; at++) {
      source.touch('/home');
    }
    await settle();

    expect(refreshes, 1, reason: 'событие — повод, а не приказ');
  });

  test('тот же каталог второй раз подписку не пересоздаёт', () async {
    // Главный предохранитель: система шлёт события старше подписки, и
    // пере-подписка на каждое перечитывание закрутила бы вечный круг.
    final dir = await dirAt('/home');
    watch.follow(dir);
    expect(source.watchers, 1);

    // Узел после перечитывания другой, а каталог тот же.
    watch.follow(await dirAt('/home'));
    watch.follow(await dirAt('/home'));

    expect(source.watchers, 1, reason: 'сравниваем путь и источник, а не узел');
  });

  test('смена каталога переносит подписку', () async {
    watch.follow(await dirAt('/home'));
    watch.follow(await dirAt('/home/docs'));

    expect(source.watchers, 1, reason: 'прежняя снята');
    expect(source.watchedPaths, ['/home/docs']);

    source.touch('/home');
    await settle();
    expect(refreshes, 0, reason: 'покинутый каталог нас больше не касается');
  });

  test('источник без умения не наблюдается', () async {
    final plain = InMemoryTreeProvider([FakeEntry.directory('/home')]);
    final dir = await plain.resolvePath().run('/home') as DirectoryNode;

    watch.follow(dir);

    expect(watch.watching, isFalse, reason: 'не умеет — и спрашивать больше не о чем');
  });

  test('пустой поток слежения не поднимает', () async {
    source.silent = true;
    watch.follow(await dirAt('/home'));
    await settle();

    expect(watch.watching, isFalse);
    expect(refreshes, 0, reason: 'следить здесь нечем — это не повод перечитывать');
  });

  test('закрытие потока снимает слежение и само ничего не читает', () async {
    watch.follow(await dirAt('/home'));

    source.close('/home');
    await settle();

    // Исчезновение каталога перечитается своим событием — система присылает
    // его раньше, чем закрывает поток. А пустой поток закрывается сразу, и
    // чтение по закрытию было бы лишним оборотом на каждом таком томе.
    expect(refreshes, 0);
    expect(watch.watching, isFalse, reason: 'подписываться заново отсюда нельзя: это круг');
  });

  test('удаление каталога перечитывает — событием, а не закрытием', () async {
    watch.follow(await dirAt('/home'));

    // Так это приходит живьём: сперва событие, следом конец потока.
    source.touch('/home');
    source.close('/home');
    await settle();

    expect(refreshes, 1);
    expect(watch.watching, isFalse);
  });

  test('ошибка потока ведёт себя как закрытие', () async {
    watch.follow(await dirAt('/home'));

    source.fail('/home');
    await settle();

    expect(refreshes, 0);
    expect(watch.watching, isFalse);
  });

  test('выключенная настройка снимает слежение на первом же событии', () async {
    watch.follow(await dirAt('/home'));
    enabled = false;

    source.touch('/home');
    await settle();

    expect(refreshes, 0);
    expect(watch.watching, isFalse);
  });

  test('выключенная настройка не подписывается вовсе', () async {
    enabled = false;
    watch.follow(await dirAt('/home'));

    expect(watch.watching, isFalse);
    expect(source.watchers, 0);
  });

  test('уход в никуда снимает слежение', () async {
    watch.follow(await dirAt('/home'));
    watch.follow(null);

    expect(watch.watching, isFalse);
    expect(source.watchers, 0);
  });

  test('разбор не оставляет ни подписки, ни отсчёта', () async {
    watch.follow(await dirAt('/home'));
    source.touch('/home');

    watch.dispose();
    await settle();

    expect(refreshes, 0, reason: 'накопленное забыто вместе с хозяином');
    expect(source.watchers, 0);
  });
}

/// Подставное дерево, умеющее говорить об изменениях.
///
/// Отдельным наследником, а не умением самого [InMemoryTreeProvider]: иначе
/// каждый виджет-тест обзавёлся бы живым отсчётом накопителя и падал бы на
/// незакрытом таймере.
class _WatchedProvider extends InMemoryTreeProvider implements WatchableSource {
  _WatchedProvider(super.entries);

  final Map<String, StreamController<void>> _watchers = {};

  /// Следить нечем: так отвечает том, который не умеет.
  bool silent = false;

  int get watchers => _watchers.length;

  List<String> get watchedPaths => _watchers.keys.toList();

  @override
  Stream<void> watchDirectory(DirectoryNode dir) {
    if (silent) {
      return const Stream<void>.empty();
    }
    final path = dir.pathString;
    final gate = StreamController<void>.broadcast(onCancel: () => _watchers.remove(path));
    _watchers[path] = gate;
    return gate.stream;
  }

  /// Здесь что-то изменилось.
  void touch(String path) => _controllerAt(path)?.add(null);

  /// Следить больше не за чем: каталог исчез.
  void close(String path) => unawaited(_controllerAt(path)?.close());

  /// Поток сломался.
  void fail(String path) => _controllerAt(path)?.addError(StateError('поток сломался'));

  StreamController<void>? _controllerAt(String path) =>
      _watchers.entries.where((one) => one.key.endsWith(path)).firstOrNull?.value;
}
