import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Файловый буфер обмена в памяти.
///
/// Без него прогон трогал бы настоящий буфер машины — и стирал бы человеку то,
/// что он только что скопировал. По той же причине, что и [FakeClipboard].
class FakeFileClipboard implements FileClipboard {
  /// Что лежит в буфере сейчас; null — файлов там нет.
  ClipboardFiles? files;

  /// Что клали, по порядку: по ним видно и сколько раз копировали.
  final List<List<FileEntry>> written = [];

  @override
  Future<void> writeFiles(List<FileEntry> entries, {required bool move}) async {
    written.add(entries);
    files = ClipboardFiles(addresses: [for (final entry in entries) entry.path], move: move, ours: true);
  }

  @override
  Future<ClipboardFiles?> readFiles() async => files;

  /// В буфер написали снаружи: чужие адреса и никакого намерения переносить
  /// (`docs/spec/file-clipboard.md`, §5).
  void putForeign(List<String> paths) {
    files = ClipboardFiles(addresses: paths);
  }

  /// В буфере не файлы — там текст, картинка или вовсе пусто.
  void clear() {
    files = null;
  }
}
