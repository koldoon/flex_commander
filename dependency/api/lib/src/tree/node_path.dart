/// Разбор и сборка строк пути, проходящих через несколько провайдеров дерева.
///
/// Путь состоит из частей вида `схема:путь`, разделённых двоеточием:
///
///     fs:/Users/koldoon/Developer/archive.zip:zip:/subdir/document.doc
///
/// Отсутствующая схема означает `fs`, поэтому обычный `/Users/koldoon` —
/// тоже валидный путь, и именно в таком виде путь показывается пользователю.
library;

/// Одна часть пути: провайдер и путь внутри него.
class NodePathPart {
  const NodePathPart(this.scheme, this.path);

  final String scheme;
  final String path;

  @override
  bool operator ==(Object other) => other is NodePathPart && other.scheme == scheme && other.path == path;

  @override
  int get hashCode => Object.hash(scheme, path);

  @override
  String toString() => '$scheme:$path';
}

class NodePath {
  NodePath(List<NodePathPart> parts)
    : assert(parts.isNotEmpty, 'Путь не может быть пустым'),
      parts = List.unmodifiable(parts);

  /// Схема по умолчанию: локальная файловая система.
  static const String defaultScheme = 'fs';

  /// Схемой считается токен из двух и более символов без разделителей пути.
  /// Ограничение снизу в два символа оставляет в покое буквы дисков Windows:
  /// `C:\Users` разбирается как путь, а не как схема `c`.
  static final RegExp _schemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]+$');

  final List<NodePathPart> parts;

  /// Часть пути, относящаяся к последнему (самому вложенному) провайдеру.
  NodePathPart get last => parts.last;

  /// Схема первой части — с неё начинается разбор пути.
  String get scheme => parts.first.scheme;

  factory NodePath.parse(String value) {
    final segments = value.split(':');
    final parts = <NodePathPart>[];
    String scheme = defaultScheme;
    final buffer = <String>[];

    void flush() {
      if (buffer.isNotEmpty) {
        // Схема без пути ("sftp:") означает корень провайдера.
        final path = buffer.join(':');
        parts.add(NodePathPart(scheme, path.isEmpty ? '/' : path));
        buffer.clear();
      }
    }

    for (final segment in segments) {
      if (_schemeRe.hasMatch(segment)) {
        flush();
        scheme = segment.toLowerCase();
      } else {
        buffer.add(segment);
      }
    }
    flush();

    if (parts.isEmpty) {
      // Строка состояла из одной только схемы: считаем это корнем провайдера.
      return NodePath([NodePathPart(scheme, '/')]);
    }
    return NodePath(parts);
  }

  /// Путь для локальной файловой системы.
  factory NodePath.local(String path) => NodePath([NodePathPart(defaultScheme, path)]);

  /// Схема `fs` в начале не печатается: пользователь видит привычный
  /// `/Users/koldoon`, а не `fs:/Users/koldoon`.
  @override
  String toString() {
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i > 0) {
        buffer.write(':');
      }
      if (i == 0 && part.scheme == defaultScheme) {
        buffer.write(part.path);
      } else {
        buffer.write(part);
      }
    }
    return buffer.toString();
  }

  /// Путь для показа пользователю: схемы провайдеров в него не входят.
  ///
  /// `fs:/home/a.zip:zip:/inner/doc.txt` → `/home/a.zip/inner/doc.txt`. Внутрь
  /// архива пользователь входит как в каталог и путь ожидает увидеть такой же;
  /// схема — это устройство приложения, а не часть адреса.
  ///
  /// Обратно такая строка не разбирается: по ней не видно, где кончается файл
  /// архива и начинается путь внутри него. Поэтому сохраняется и передаётся
  /// по-прежнему [toString] — со схемами.
  String get displayString {
    final buffer = StringBuffer(_trimSlash(parts.first.path));

    for (final part in parts.skip(1)) {
      final path = _trimSlash(part.path);
      if (path.isEmpty) {
        // Корень вложенного провайдера: сам он ничего к пути не добавляет.
        continue;
      }
      buffer.write(path.startsWith('/') ? path : '/$path');
    }

    final result = buffer.toString();
    return result.isEmpty ? '/' : result;
  }

  static String _trimSlash(String path) =>
      path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : (path == '/' ? '' : path);

  @override
  bool operator ==(Object other) =>
      other is NodePath &&
      other.parts.length == parts.length &&
      List.generate(parts.length, (i) => other.parts[i] == parts[i]).every((equal) => equal);

  @override
  int get hashCode => Object.hashAll(parts);
}
