import 'package:fc_platform/fc_platform.dart';
import 'package:flutter_test/flutter_test.dart';

/// Где лежит приложение — по пути его исполняемого файла
/// (`docs/spec/build-info.md`).
void main() {
  test('бандл находится по пути внутри него', () {
    expect(
      BuildInfoChannel.bundleOf('/Applications/flex_commander.app/Contents/MacOS/flex_commander'),
      '/Applications/flex_commander.app',
    );
  });

  test('пробелы и точки в пути ничему не мешают', () {
    expect(
      BuildInfoChannel.bundleOf('/Volumes/My Disk/flex commander.app/Contents/MacOS/flex_commander'),
      '/Volumes/My Disk/flex commander.app',
    );
  });

  test('не из бандла — значит бандла нет', () {
    // Так живут проверки и `flutter run`: обновляться неоткуда и некуда.
    expect(BuildInfoChannel.bundleOf('/opt/flutter/bin/cache/artifacts/flutter_tester'), isEmpty);
    expect(BuildInfoChannel.bundleOf(''), isEmpty);
  });
}
