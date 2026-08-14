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
  bool operator ==(Object other) =>
      other is NodePathPart && other.scheme == scheme && other.path == path;

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
  factory NodePath.local(String path) =>
      NodePath([NodePathPart(defaultScheme, path)]);

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

  @override
  bool operator ==(Object other) =>
      other is NodePath &&
      other.parts.length == parts.length &&
      List.generate(parts.length, (i) => other.parts[i] == parts[i])
          .every((equal) => equal);

  @override
  int get hashCode => Object.hashAll(parts);
}
