import 'dart:convert';

import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ответ GitHub: то, что приезжает по сети, разбирается отдельно от неё
/// (`docs/spec/self-update.md`, §3).
void main() {
  /// Ответ API — такой же, каким он приходит с живого сервера.
  String body({
    String tag = 'v0.0.72',
    String notes = 'Что менялось',
    List<Map<String, Object?>> assets = const [
      {
        'name': 'flex_commander-v0.0.72-macos-arm64.zip',
        'browser_download_url': 'https://example.test/v0.0.72.zip',
        'digest': 'sha256:f34bfe1be6ad2bee4acce980f101631346364013618da1de2f54ebd720a9e38d',
        'size': 24235592,
      },
    ],
  }) => jsonEncode({'tag_name': tag, 'body': notes, 'assets': assets});

  test('из ответа берутся тег, заметки и файл с суммой', () {
    final release = GithubReleases.parse(body())!;

    expect(release.version, const AppVersion(0, 0, 72));
    expect(release.tag, 'v0.0.72');
    expect(release.notes, 'Что менялось');

    final asset = release.assetFor('arm64')!;
    expect(asset.name, 'flex_commander-v0.0.72-macos-arm64.zip');
    expect(asset.size, 24235592);
    expect(asset.sha256, 'f34bfe1be6ad2bee4acce980f101631346364013618da1de2f54ebd720a9e38d');
    expect(asset.sha256, isNot(startsWith('sha256:')), reason: 'приставка протокола в сумму не входит');
  });

  test('файл выбирается по архитектуре, а не по порядку', () {
    final release =
        GithubReleases.parse(
          body(
            assets: const [
              {'name': 'flex_commander-v0.0.72-macos-x64.zip', 'browser_download_url': 'https://example.test/x64.zip'},
              {
                'name': 'flex_commander-v0.0.72-macos-arm64.zip',
                'browser_download_url': 'https://example.test/arm64.zip',
              },
            ],
          ),
        )!;

    expect(release.assetFor('arm64')?.url, 'https://example.test/arm64.zip');
    expect(release.assetFor('x64')?.url, 'https://example.test/x64.zip');
    expect(release.assetFor('riscv'), isNull);
  });

  test('файл без названной суммы приезжает с пустой, а не с чужой', () {
    final release =
        GithubReleases.parse(
          body(
            assets: const [
              {
                'name': 'flex_commander-v0.0.72-macos-arm64.zip',
                'browser_download_url': 'https://example.test/a.zip',
                'digest': 'md5:d41d8cd98f00b204e9800998ecf8427e',
              },
            ],
          ),
        )!;

    expect(release.assetFor('arm64')?.sha256, isEmpty, reason: 'сверять md5 нам нечем');
  });

  test('ответ без тега — не выпуск', () {
    expect(GithubReleases.parse('{"body": "нет тега"}'), isNull);
    expect(GithubReleases.parse('[]'), isNull);
    expect(GithubReleases.parse(jsonEncode({'tag_name': 'nightly'})), isNull, reason: 'не версия');
  });

  test('выпуск без файлов разбирается, но ставить из него нечего', () {
    final release = GithubReleases.parse(body(assets: const []))!;

    expect(release.assets, isEmpty);
    expect(release.assetFor('arm64'), isNull);
  });
}
