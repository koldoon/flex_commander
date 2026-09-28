import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Чем читать картинки, на которые ссылается документ.
///
/// Через **тот же источник**, откуда пришёл сам документ, а не через `dart:io`:
/// `.md` открывают и в архиве, и по `ssh`, и соседний файл там читается
/// контрактом, как и всё остальное (`docs/spec/markdown-viewer.md`, §9).
///
/// Разбор пути ведёт корень дерева (`Application.contentAt`), а не панель:
/// путь, собранный от документа, к месту, где стоит панель, отношения не имеет.
FcImageResolver imageResolverOf(ViewerRequest request) {
  final base = _directoryOf(request.entry);
  final app = request.app;

  return (path) async {
    final full = _join(base, path);
    final content = app.contentAt(FileEntry(name: _nameOf(full), kind: EntryKind.file, path: full));

    final bytes = <int>[];
    await for (final chunk in content.read()) {
      bytes.addAll(chunk);
    }

    return Uint8List.fromList(bytes);
  };
}

/// Каталог, в котором лежит документ.
String _directoryOf(FileEntry entry) {
  if (entry.directoryPath.isNotEmpty) {
    return entry.directoryPath;
  }
  final cut = entry.path.lastIndexOf('/');

  return cut <= 0 ? '/' : entry.path.substring(0, cut);
}

String _nameOf(String path) {
  final cut = path.lastIndexOf('/');

  return cut < 0 ? path : path.substring(cut + 1);
}

/// Склеить путь документа с относительным путём из него.
///
/// Разделитель — `/`: так пишут в markdown, и так же устроены все наши
/// источники (диск, архив, ssh, ftp). Появится источник с другим разделителем —
/// сломается это место первым, и сказать об этом надо здесь.
String _join(String base, String relative) {
  if (relative.startsWith('/')) {
    return relative;
  }

  final parts = <String>[...base.split('/').where((part) => part.isNotEmpty)];
  for (final part in relative.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
      continue;
    }
    parts.add(part);
  }

  return '/${parts.join('/')}';
}
