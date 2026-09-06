import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/listing_cache.dart';
import 'package:flutter_test/flutter_test.dart';

List<FakeEntry> _entries() => [
  FakeEntry.directory('/home'),
  FakeEntry.directory('/home/docs'),
  FakeEntry.file('/home/docs/a.txt', size: 100),
  FakeEntry.directory('/home/bin'),
  FakeEntry.file('/home/bin/tool', size: 400),
  FakeEntry.file('/home/notes.txt', size: 50),
  FakeEntry.file('/home/.hidden', size: 10),
];

/// Провайдер, чтение которого можно задержать.
///
/// Без задержки мгновенный показ не отличить от обычного чтения: в памяти оно
/// успевает за одну микрозадачу, и оба выглядят одинаково быстрыми.
class _HeldProvider extends InMemoryTreeProvider {
  _HeldProvider() : super(_entries());

  Completer<void>? _gate;

  /// Следующие чтения ждут [release].
  void hold() => _gate ??= Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    final inner = super.getDirectoryListing();
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      await _gate?.future;
      return op.delegate(inner, params);
    });
  }
}

/// Кеш каталогов: подсказка, которая всегда догоняется чтением.
///
/// Спецификация — `docs/spec/listing-cache.md`.
void main() {
  /// Даёт петле и микрозадачам дойти до конца — но не ждёт задержанного чтения.
  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('память', () {
    late InMemoryTreeProvider provider;
    late DateTime now;

    ListingCache build({bool enabled = true, int limit = 64, int ttl = 300}) =>
        ListingCache(enabled: () => enabled, limit: () => limit, ttl: () => Duration(seconds: ttl), clock: () => now);

    DirectoryNode dir(String name) => DirectoryNode(provider: provider, name: name, parent: provider.rootDirectory);

    List<FsNode> listing(String name) => [FileNode(provider: provider, name: name)];

    setUp(() {
      provider = InMemoryTreeProvider(_entries());
      now = DateTime(2026, 9, 6, 12);
    });

    test('положенное отдаётся обратно', () {
      final cache = build();
      final docs = dir('docs');
      cache.put(docs, listing('a.txt'), includeHidden: false);

      expect(cache.take(docs, includeHidden: false)?.single.name, 'a.txt');
    });

    test('показ скрытых разводит записи', () {
      final cache = build();
      final docs = dir('docs');
      cache.put(docs, listing('a.txt'), includeHidden: false);

      // Список без скрытых не годится панели, которая их показывает.
      expect(cache.take(docs, includeHidden: true), isNull);
      expect(cache.take(docs, includeHidden: false), isNotNull);
    });

    test('чужому провайдеру список не отдаётся', () {
      final cache = build();
      cache.put(dir('docs'), listing('a.txt'), includeHidden: false);

      // Тот же путь, но другой источник той же схемы: это разные каталоги.
      final other = InMemoryTreeProvider(_entries());
      final theirs = DirectoryNode(provider: other, name: 'docs', parent: other.rootDirectory);
      expect(cache.take(theirs, includeHidden: false), isNull);
    });

    test('предел вытесняет самое давнее', () {
      final cache = build(limit: 2);
      cache.put(dir('a'), listing('1'), includeHidden: false);
      cache.put(dir('b'), listing('2'), includeHidden: false);
      cache.put(dir('c'), listing('3'), includeHidden: false);

      expect(cache.length, 2);
      expect(cache.take(dir('a'), includeHidden: false), isNull);
      expect(cache.take(dir('b'), includeHidden: false), isNotNull);
      expect(cache.take(dir('c'), includeHidden: false), isNotNull);
    });

    test('обращение освежает запись', () {
      final cache = build(limit: 2);
      cache.put(dir('a'), listing('1'), includeHidden: false);
      cache.put(dir('b'), listing('2'), includeHidden: false);
      cache.take(dir('a'), includeHidden: false);
      cache.put(dir('c'), listing('3'), includeHidden: false);

      // Вытесняется давно не нужное, а не давно прочитанное.
      expect(cache.take(dir('a'), includeHidden: false), isNotNull);
      expect(cache.take(dir('b'), includeHidden: false), isNull);
    });

    test('просроченная запись не отдаётся и не занимает места', () {
      final cache = build(ttl: 300);
      cache.put(dir('docs'), listing('a.txt'), includeHidden: false);

      now = now.add(const Duration(seconds: 301));

      expect(cache.take(dir('docs'), includeHidden: false), isNull);
      expect(cache.length, 0);
    });

    test('закрытие провайдера уносит его записи', () {
      final cache = build();
      final other = InMemoryTreeProvider(_entries());
      cache.put(dir('docs'), listing('a.txt'), includeHidden: false);
      cache.put(
        DirectoryNode(provider: other, name: 'inner', parent: other.rootDirectory),
        listing('b.txt'),
        includeHidden: false,
      );

      cache.forgetProvider(other);

      expect(cache.length, 1);
      expect(cache.take(dir('docs'), includeHidden: false), isNotNull);
    });

    test('«забыть» уносит обе записи каталога', () {
      final cache = build();
      final docs = dir('docs');
      cache.put(docs, listing('a.txt'), includeHidden: false);
      cache.put(docs, listing('.hidden'), includeHidden: true);

      cache.forget(docs);

      expect(cache.length, 0);
    });

    test('выключенный кеш не помнит ничего', () {
      final cache = build(enabled: false);
      cache.put(dir('docs'), listing('a.txt'), includeHidden: false);

      expect(cache.length, 0);
      expect(cache.take(dir('docs'), includeHidden: false), isNull);
    });
  });

  group('реестр', () {
    test('о закрытии провайдера реестр сообщает', () async {
      final registry = ProviderRegistry(root: InMemoryTreeProvider(_entries()));
      final inner = InMemoryReadOnlyProvider();
      registry.register('zip', () => TaskOperation<FsNode, TreeProvider>((op, host) async => inner));

      final closed = <TreeProvider>[];
      registry.onProviderClosed(closed.add);

      final host = FileNode(provider: registry.root, name: 'a.zip', parent: registry.root.rootDirectory);
      final acquire = registry.acquire()..start(AcquireParams('zip', host));
      final lease = await acquire.result;
      expect(closed, isEmpty);

      await lease.release();

      expect(closed, [inner]);
    });
  });

  group('панель', () {
    late _HeldProvider provider;
    late ListingCache cache;
    late TestPanel panel;

    setUp(() async {
      provider = _HeldProvider();
      cache = ListingCache(enabled: () => true, limit: () => 64, ttl: () => const Duration(seconds: 300));
      panel = testPanel(provider: provider, settings: PanelSettings.defaults('/home'), cache: cache);
      await panel.openPath('/home');
    });

    tearDown(() => panel.dispose());

    /// Войти в каталог под курсором.
    Future<void> enter(String name) async {
      panel.setCursorToName(name);
      await panel.enterCurrent();
    }

    test('возврат наверх рисует список сразу и читает ровно раз', () async {
      await enter('docs');
      final reads = provider.listings;

      provider.hold();
      final up = panel.goUp();
      await pump();

      // Список уже на экране, и панель не занята: клавиши её, курсор ходит.
      expect(panel.path, '/home');
      expect(panel.entries.map((e) => e.name), contains('notes.txt'));
      expect(panel.busy, isFalse);
      expect(panel.statusText, isNull);

      provider.release();
      await up;

      expect(provider.listings, reads + 1);
    });

    test('курсор стоит на каталоге, из которого вышли', () async {
      await enter('docs');
      provider.hold();
      final up = panel.goUp();
      await pump();

      expect(panel.currentEntry?.name, 'docs');

      provider.release();
      await up;
      expect(panel.currentEntry?.name, 'docs');
    });

    test('изменившееся содержимое доезжает само', () async {
      await enter('docs');
      provider.hold();
      final up = panel.goUp();
      await pump();

      expect(panel.entries.map((e) => e.name), isNot(contains('fresh.txt')));

      provider.add(FakeEntry.file('/home/fresh.txt', size: 1));
      provider.release();
      await up;

      expect(panel.entries.map((e) => e.name), contains('fresh.txt'));
    });

    test('стрелка, нажатая до прихода обновления, не отыгрывается назад', () async {
      await enter('docs');
      provider.hold();
      final up = panel.goUp();
      await pump();

      panel.setCursorToName('notes.txt');
      provider.add(FakeEntry.file('/home/fresh.txt', size: 1));
      provider.release();
      await up;

      // Имя для второго применения берётся то, которое стоит в момент прихода.
      expect(panel.currentEntry?.name, 'notes.txt');
    });

    test('равный список не пересобирает таблицу', () async {
      await enter('docs');
      provider.hold();
      final up = panel.goUp();
      await pump();

      panel.setCursorToName('notes.txt');
      panel.toggleCurrentMark();
      final generation = panel.session.generation;

      provider.release();
      await up;

      // Ничего не изменилось — и таблица не пересобирается: иначе каждый подъём
      // наверх ронял бы её на ровном месте, а вместе с ней пометку, которая
      // живёт узлами.
      expect(panel.session.generation, generation);
      expect(panel.markedPaths, contains('/home/notes.txt'));
    });

    test('изменившийся список таблицу пересобирает', () async {
      await enter('docs');
      provider.hold();
      final up = panel.goUp();
      await pump();
      final generation = panel.session.generation;

      provider.add(FakeEntry.file('/home/fresh.txt', size: 1));
      provider.release();
      await up;

      expect(panel.session.generation, greaterThan(generation));
    });

    test('оборвавшееся чтение оставляет список на экране', () async {
      await enter('docs');
      provider.denied['/home'] = const FsError('/home', FsErrorKind.io);

      await panel.goUp();

      expect(panel.entries.map((e) => e.name), contains('notes.txt'));
      expect(panel.phase, PanelPhase.idle);
      expect(panel.statusText, isNotNull);

      // Запись выброшена: следующий приход не покажет её опять.
      provider.denied.remove('/home');
      await enter('docs');
      provider.hold();
      final again = panel.goUp();
      await pump();
      expect(panel.busy, isTrue);
      provider.release();
      await again;
    });

    test('исчезнувший каталог показывать нечего', () async {
      await enter('docs');
      provider.denied['/home'] = const FsError('/home', FsErrorKind.notFound);

      await panel.goUp();

      expect(panel.phase, PanelPhase.error);
    });

    test('перечитывание идёт мимо памяти', () async {
      await enter('docs');
      await panel.goUp();

      provider.hold();
      final reload = panel.reload();
      await pump();

      // Это ответ на «показалось не то»: показывать в ответ то же самое было бы
      // издевательством.
      expect(panel.busy, isTrue);
      expect(panel.statusText, 'Loading…');

      provider.release();
      await reload;
    });

    test('выключенный кеш возвращает прежнее поведение', () async {
      var enabled = true;
      final off = ListingCache(enabled: () => enabled, limit: () => 64, ttl: () => const Duration(seconds: 300));
      final source = _HeldProvider();
      final it = testPanel(provider: source, settings: PanelSettings.defaults('/home'), cache: off);
      addTearDown(it.dispose);
      await it.openPath('/home');
      it.setCursorToName('docs');
      await it.enterCurrent();
      enabled = false;

      source.hold();
      final up = it.goUp();
      await pump();

      // Ни одного показа до чтения: панель занята и стоит там, где стояла.
      expect(it.busy, isTrue);
      expect(it.path, '/home/docs');

      source.release();
      await up;
      expect(it.path, '/home');
    });

    test('прочитанное одной панелью достаётся другой даром', () async {
      final other = testPanel(
        provider: provider,
        settings: PanelSettings.defaults('/home'),
        cache: cache,
        id: PanelId.right,
      );
      addTearDown(other.dispose);

      // Левая уже прочитала `/home` в setUp.
      provider.hold();
      final opening = other.openPath('/home');
      await pump();

      expect(other.entries.map((e) => e.name), contains('notes.txt'));
      expect(other.busy, isFalse);

      provider.release();
      await opening;
    });
  });
}
