import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/listing_cache.dart';
import 'package:flex_commander/state/shell_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Панель догоняет чужие изменения (`docs/spec/directory-watch.md`, §6).
void main() {
  const window = Duration(milliseconds: 20);

  late _WatchedProvider provider;
  late TestPanel panel;

  /// Разобрана ли панель самим тестом: второй разбор — ошибка, и правильно.
  late bool disposed;

  setUp(() {
    provider = _WatchedProvider();
    disposed = false;
  });

  tearDown(() {
    if (!disposed) {
      panel.dispose();
    }
  });

  /// Дать делам доехать: чтение в памяти успевает за микрозадачу, а
  /// накопление — за своё окно.
  Future<void> pump({int rounds = 8}) async {
    for (var at = 0; at < rounds; at++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<TestPanel> open({ListingCache? cache, MeasuredSizes? sizes, bool watch = true}) async {
    panel = testPanel(
      provider: provider,
      settings: PanelSettings(path: '/home'),
      cache: cache,
      sizes: sizes,
      watchDirectories: watch,
      watchDelay: window,
    );
    await panel.openPath('/home');
    await pump();
    return panel;
  }

  Future<void> settle() async {
    await Future<void>.delayed(window * 4);
    await pump();
  }

  test('событие перечитывает каталог', () async {
    await open();
    final before = provider.listings;

    provider.add(FakeEntry.file('/home/new.txt', size: 7));
    provider.touch('/home');
    await settle();

    expect(provider.listings, greaterThan(before), reason: 'изменили не мы — догнали');
    expect(panel.entries.map((one) => one.name), contains('new.txt'));
  });

  test('пачка событий стоит одного чтения', () async {
    await open();
    final before = provider.listings;

    // Так это приходит живьём: двадцать файлов — четыре сотни событий.
    for (var at = 0; at < 50; at++) {
      provider.touch('/home');
    }
    await settle();

    expect(provider.listings - before, 1, reason: 'событие — повод, а не приказ');
  });

  test('догоняющее чтение не делает панель занятой', () async {
    await open();

    provider.add(FakeEntry.file('/home/new.txt', size: 7));
    provider.touch('/home');
    await settle();

    expect(panel.busy, isFalse, reason: 'клавиатура её — ей никто не мешает');
    expect(panel.phase, PanelPhase.idle);
  });

  test('курсор и пометка остаются на месте', () async {
    await open();
    panel.setCursorToName('notes.txt');
    panel.mark(panel.currentEntry!);
    await pump();
    final marked = panel.markedPaths.toSet();

    provider.add(FakeEntry.file('/home/new.txt', size: 7));
    provider.touch('/home');
    await settle();

    expect(panel.currentEntry?.name, 'notes.txt');
    expect(panel.markedPaths.toSet(), marked, reason: 'пометка живёт путями и чтение переживает');
  });

  test('равный список ничего не двигает', () async {
    // Система присылает события, случившиеся до подписки: сразу после входа в
    // каталог почти всегда прилетает одно ложное.
    await open();
    final generation = panel.session.generation;

    provider.touch('/home');
    await settle();

    expect(panel.session.generation, generation, reason: 'таблицу пересобирать не за что');
  });

  test('запись памяти выбрасывается: соседняя панель видит новое', () async {
    final cache = ListingCache(enabled: () => true, limit: () => 16, ttl: () => const Duration(minutes: 5));
    await open(cache: cache);

    provider.add(FakeEntry.file('/home/new.txt', size: 7));
    provider.touch('/home');
    await settle();

    // Второй панели памяти о старом списке достаться не должно.
    final other = testPanel(
      provider: provider,
      settings: PanelSettings(path: '/home'),
      cache: cache,
      watchDirectories: false,
    );
    addTearDown(other.dispose);
    await other.openPath('/home');
    await pump();

    expect(other.entries.map((one) => one.name), contains('new.txt'));
  });

  test('событие забывает каталог и предков, но не поддерево', () async {
    final sizes = MeasuredSizes();
    await open(sizes: sizes);

    // Три записи: сам каталог, его предок и ветвь под ним. Считались они
    // долго, а событие слежения говорит только о `/home`.
    final home = (await provider.resolvePath().run('/home'))! as DirectoryNode;
    final root = provider.rootDirectory;
    final deep = (await provider.resolvePath().run('/home/docs'))! as DirectoryNode;
    const totals = DirectoryTotals(bytes: 1, workBytes: 1, entries: 1);
    for (final dir in [home, root, deep]) {
      sizes.remember(dir, totals);
    }

    provider.touch('/home');
    await settle();

    expect(sizes.take(home), isNull, reason: 'изменился он сам');
    expect(sizes.take(root), isNull, reason: 'и сумма выше по дереву вместе с ним');
    expect(sizes.take(deep), totals, reason: 'а про поддерево событие ничего и не говорило');
  });

  test('уход из каталога снимает слежение', () async {
    await open();
    expect(provider.watchers, 1);

    await panel.openPath('/home/docs');
    await pump();

    expect(provider.watchers, 1, reason: 'подписка одна и она на новом месте');
    expect(provider.watchedPaths.single, endsWith('/home/docs'));
  });

  test('закрытая сессия слежения не держит', () async {
    await open();
    expect(provider.watchers, 1);

    panel.dispose();
    disposed = true;
    await settle();

    expect(provider.watchers, 0);
  });

  test('умолчание настройки и умолчание накопителя — одно число', () async {
    // Два места, называющих одно, однажды разойдутся: настройку правят в окне,
    // а накопитель живёт в общем наборе, и константу из него в поле не вписать.
    await open();
    expect(ShellSettings.defaultWatchDelay, Settle.defaultQuiet.inMilliseconds);
  });

  test('выключенная настройка не подписывается вовсе', () async {
    await open(watch: false);

    expect(provider.watchers, 0);

    final before = provider.listings;
    provider.touch('/home');
    await settle();

    expect(provider.listings, before, reason: 'остаётся Cmd-R');
  });
}

/// Подставное дерево, умеющее говорить об изменениях.
///
/// Отдельным наследником, а не умением общего [InMemoryTreeProvider]: сделай
/// это умением всех — и каждый виджет-тест обзавёлся бы живым отсчётом
/// накопителя, то есть падал бы на незакрытом таймере.
class _WatchedProvider extends InMemoryTreeProvider implements WatchableSource {
  _WatchedProvider()
    : super([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/notes.txt', size: 50),
        FakeEntry.file('/home/tool.sh', size: 10),
      ]);

  final Map<String, StreamController<void>> _watchers = {};

  int get watchers => _watchers.length;

  List<String> get watchedPaths => _watchers.keys.toList();

  @override
  Stream<void> watchDirectory(DirectoryNode dir) {
    final path = dir.pathString;
    final gate = StreamController<void>.broadcast(onCancel: () => _watchers.remove(path));
    _watchers[path] = gate;
    return gate.stream;
  }

  /// Здесь что-то изменилось.
  void touch(String path) {
    for (final one in _watchers.entries) {
      if (one.key.endsWith(path)) {
        one.value.add(null);
      }
    }
  }
}
