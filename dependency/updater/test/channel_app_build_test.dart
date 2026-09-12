import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Где лежит приложение — по пути его исполняемого файла
/// (`docs/spec/self-update.md`, §7).
void main() {
  test('бандл находится по пути внутри него', () {
    expect(
      ChannelAppBuild.bundleOf('/Applications/flex_commander.app/Contents/MacOS/flex_commander'),
      '/Applications/flex_commander.app',
    );
  });

  test('пробелы и точки в пути ничему не мешают', () {
    expect(
      ChannelAppBuild.bundleOf('/Volumes/My Disk/flex commander.app/Contents/MacOS/flex_commander'),
      '/Volumes/My Disk/flex commander.app',
    );
  });

  test('не из бандла — значит бандла нет', () {
    // Так живут проверки и `flutter run`: обновляться неоткуда и некуда.
    expect(ChannelAppBuild.bundleOf('/opt/flutter/bin/cache/artifacts/flutter_tester'), isEmpty);
    expect(ChannelAppBuild.bundleOf(''), isEmpty);
  });
}
