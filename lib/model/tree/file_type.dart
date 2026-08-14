import 'dart:io';

/// Тип объекта файловой системы.
///
/// Символы соответствуют первому символу строки режима доступа в стиле `ls`
/// ("drwxr-xr-x") — так же, как в референсной реализации.
enum FileType {
  regular('-'),
  directory('d'),
  symbolicLink('l'),
  socket('s'),
  fifo('p'),
  blockSpecial('b'),
  characterSpecial('c'),
  unknown('?');

  const FileType(this.attributeChar);

  final String attributeChar;

  /// Разбор первого символа строки режима: "drwxr-xr-x" -> [directory].
  static FileType fromAttributeChar(String char) {
    for (final type in values) {
      if (type.attributeChar == char) {
        return type;
      }
    }
    return unknown;
  }

  /// Разбор типа из `dart:io`.
  static FileType fromEntityType(FileSystemEntityType type) {
    return switch (type) {
      FileSystemEntityType.file => regular,
      FileSystemEntityType.directory => directory,
      FileSystemEntityType.link => symbolicLink,
      FileSystemEntityType.pipe => fifo,
      FileSystemEntityType.unixDomainSock => socket,
      _ => unknown,
    };
  }
}
