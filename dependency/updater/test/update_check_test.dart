import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Решение об обновлении: ни сети, ни файлов — только правила
/// (`docs/spec/self-update.md`, §4).
void main() {
  /// Приложение, каким его видит проверка.
  AppBuild build({String? version = '0.0.72', String architecture = 'arm64', bool canReplace = true}) =>
      _FakeBuild(version: version, architecture: architecture, canReplace: canReplace);

  /// Выпуск с одним файлом под названную архитектуру.
  ReleaseInfo release(String tag, {String architecture = 'arm64', String sha256 = 'abc123', String notes = ''}) =>
      ReleaseInfo(
        version: AppVersion.parse(tag)!,
        tag: tag,
        notes: notes,
        assets: [
          ReleaseAsset(
            name: 'flex_commander-$tag-macos-$architecture.zip',
            url: 'https://example.test/$tag.zip',
            sha256: sha256,
            size: 1024,
          ),
        ],
      );

  Future<UpdateCheckResult> check(AppBuild self, ReleaseInfo? latest) =>
      UpdateCheck(build: self, source: _FakeSource(latest)).run();

  test('выпуск новее — предлагается вместе со своим файлом', () async {
    final result = await check(build(), release('v0.0.73', notes: 'Что менялось'));

    expect(result, isA<UpdateAvailable>());
    final found = result as UpdateAvailable;
    expect(found.release.version, const AppVersion(0, 0, 73));
    expect(found.release.notes, 'Что менялось');
    expect(found.asset.name, contains('macos-arm64'));
  });

  test('тот же выпуск или старше — обновляться нечем', () async {
    expect(await check(build(), release('v0.0.72')), isA<AlreadyLatest>());
    expect(await check(build(), release('v0.0.71')), isA<AlreadyLatest>());
  });

  test('сборка с машины разработчика себя не обновляет', () async {
    // `1.0.0` новее любого выпуска — и это ровно то, что нужно.
    expect(await check(build(version: '1.0.0'), release('v0.0.73')), isA<AlreadyLatest>());
  });

  test('своей версии не знаем — сравнивать не с чем', () async {
    final result = await check(build(version: null), release('v0.0.73'));

    expect((result as UpdateImpossible).reason, UpdateObstacle.unknownVersion);
  });

  test('выпусков нет вовсе', () async {
    final result = await check(build(), null);

    expect((result as UpdateImpossible).reason, UpdateObstacle.noReleases);
  });

  test('сборки под этот процессор нет — чужую не подсовываем', () async {
    final result = await check(build(architecture: 'x64'), release('v0.0.73'));

    expect((result as UpdateImpossible).reason, UpdateObstacle.noAssetForArchitecture);
  });

  test('суммы нет — ставить непроверяемое нельзя', () async {
    final result = await check(build(), release('v0.0.73', sha256: ''));

    expect((result as UpdateImpossible).reason, UpdateObstacle.noChecksum);
  });

  test('подменить себя некуда — говорим до загрузки, а не после', () async {
    final result = await check(build(canReplace: false), release('v0.0.73'));

    expect((result as UpdateImpossible).reason, UpdateObstacle.cannotReplaceItself);
  });

  test('«не новее» отвечают раньше, чем смотрят на архитектуру и права', () async {
    // Иначе на своей же свежей сборке человек услышал бы «нет файла под ваш
    // процессор» — ответ верный по букве и бессмысленный по делу.
    final result = await check(build(architecture: 'x64', canReplace: false), release('v0.0.72'));

    expect(result, isA<AlreadyLatest>());
  });
}

class _FakeBuild implements AppBuild {
  _FakeBuild({required String? version, required this.architecture, required bool canReplace})
    : version = version == null ? null : AppVersion.parse(version),
      canReplaceItself = canReplace;

  @override
  final AppVersion? version;

  @override
  final String architecture;

  @override
  final bool canReplaceItself;

  @override
  String get bundlePath => '/Applications/flex_commander.app';
}

class _FakeSource implements ReleaseSource {
  _FakeSource(this._latest);

  final ReleaseInfo? _latest;

  @override
  Future<ReleaseInfo?> latest() async => _latest;
}
