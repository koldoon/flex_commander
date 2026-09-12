import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обновление целиком: когда спрашивать, о чём молчать и что откладывать
/// (`docs/spec/self-update.md`, §8).
void main() {
  late Directory cache;
  late UpdaterSettings memory;
  late int saves;
  late DateTime now;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('fc_service');
    memory = UpdaterSettings();
    saves = 0;
    now = DateTime(2026, 9, 12, 10);
  });

  tearDown(() async {
    if (await cache.exists()) {
      await cache.delete(recursive: true);
    }
  });

  ReleaseInfo release(String tag) => ReleaseInfo(
    version: AppVersion.parse(tag)!,
    tag: tag,
    notes: 'заметки',
    assets: [
      ReleaseAsset(name: 'flex_commander-$tag-macos-arm64.zip', url: 'https://example.test/$tag', sha256: 'abc'),
    ],
  );

  UpdateService service({ReleaseInfo? latest}) => UpdateService(
    build: _FakeBuild(),
    source: _FakeSource(latest),
    processes: FakeProcessRunner.new,
    settings: () => memory,
    save: () => saves++,
    cache: cache,
    now: () => now,
  );

  test('при запуске спрашивают раз в сутки, не чаще', () async {
    final updates = service(latest: release('v0.0.73'));

    expect(await updates.check(), isA<UpdateAvailable>());
    expect(memory.lastCheck, isNotEmpty, reason: 'дата проверки записана');
    expect(saves, 1);

    // Второй запуск в тот же день: сервер не спрашивают вовсе.
    expect(await updates.check(), isA<AlreadyLatest>());
    expect(saves, 1, reason: 'записывать нечего — мы и не спрашивали');

    now = now.add(const Duration(days: 1, minutes: 1));
    expect(await updates.check(), isA<UpdateAvailable>());
  });

  test('человек спрашивает — отвечают всегда, даже сегодня и повторно', () async {
    final updates = service(latest: release('v0.0.73'));
    await updates.check();

    expect(await updates.check(byHand: true), isA<UpdateAvailable>());
    expect(saves, 2, reason: 'спросили — значит дата новая');
  });

  test('выключенная проверка при запуске молчит, а по просьбе отвечает', () async {
    memory.checkAtStartup = false;
    final updates = service(latest: release('v0.0.73'));

    expect(await updates.check(), isA<AlreadyLatest>());
    expect(await updates.check(byHand: true), isA<UpdateAvailable>(), reason: 'кнопка «Check now» живая всегда');
  });

  test('отложенный выпуск не предлагают сам собой, но по просьбе показывают', () async {
    final updates = service(latest: release('v0.0.73'));
    updates.postpone(release('v0.0.73'));
    expect(memory.postponed, 'v0.0.73');

    now = now.add(const Duration(days: 2));
    expect(await updates.check(), isA<AlreadyLatest>(), reason: 'сказали «Позже» — не навязываемся');

    expect(await updates.check(byHand: true), isA<UpdateAvailable>());
  });

  test('отложили одну версию — следующая всё равно предложится', () async {
    final updates = service(latest: release('v0.0.74'));
    memory.postponed = 'v0.0.73';

    expect(await updates.check(), isA<UpdateAvailable>());
  });

  test('дата проверки ставится и после неудачи', () async {
    // Иначе недоступный сервер спрашивался бы на каждом запуске, а ответ от
    // этого не изменится.
    final updates = service(latest: null);

    expect(await updates.check(), isA<UpdateImpossible>());
    expect(memory.lastCheck, isNotEmpty);
  });

  group('память', () {
    test('пора спрашивать, если ещё ни разу', () {
      expect(UpdaterSettings().dueAt(now), isTrue);
    });

    test('часы перевели назад — спрашиваем, а не ждём сутки', () {
      final settings = UpdaterSettings(lastCheck: now.add(const Duration(days: 3)).toIso8601String());

      expect(settings.dueAt(now), isTrue);
    });

    test('выключенная проверка не наступает никогда', () {
      final settings = UpdaterSettings(checkAtStartup: false);

      expect(settings.dueAt(now), isFalse);
    });

    test('нетронутые настройки пишут о себе только флажок', () {
      final map = <String, dynamic>{};
      UpdaterSettings().toMap(map);

      expect(map.keys, ['checkAtStartup']);
    });
  });
}

class _FakeBuild implements AppBuild {
  @override
  AppVersion? get version => const AppVersion(0, 0, 72);

  @override
  String get architecture => 'arm64';

  @override
  String get bundlePath => '/Applications/flex_commander.app';

  @override
  bool get canReplaceItself => true;
}

class _FakeSource implements ReleaseSource {
  _FakeSource(this._latest);

  final ReleaseInfo? _latest;

  @override
  Future<ReleaseInfo?> latest() async => _latest;
}
