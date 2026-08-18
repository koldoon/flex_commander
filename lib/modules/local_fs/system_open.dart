import 'dart:io';

/// Реализация [SystemOpener] по умолчанию: `open` на macOS, `start` на Windows,
/// `xdg-open` на Linux — то же самое делал референс, вызывая `bin/open`.
Future<void> openWithSystem(String path) async {
  if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}
