/// Вид ошибки доступа к дереву.
enum FsErrorKind {
  notFound,
  permissionDenied,
  notADirectory,
  alreadyExists,
  invalidName,
  targetInsideSource,
  notSupported,

  /// Протокол, которого никто не умеет: `ssh://` без модуля SSH.
  ///
  /// Отдельно от [notSupported]: там речь о том, чего не умеет **источник**
  /// (писать в архив, открытый на просмотр), а здесь — о том, что открывать
  /// адрес просто нечем. `path` в такой ошибке — имя протокола.
  unsupportedScheme,

  /// Строка не разбирается ни как путь, ни как адрес.
  ///
  /// «Blah» — это не путь (не абсолютный) и не адрес (нет протокола), и
  /// говорить о нём «не найдено» или «протокол не поддерживается» одинаково
  /// неверно: не найдено — значит искали, а искать тут нечего.
  invalidAddress,

  io,
}

/// Ошибка чтения или изменения дерева.
///
/// Общая обеим сторонам: случается она у источника, а показывают её на экране.
/// Значение — только строки и перечислимое, поэтому границу переживает как
/// есть (`spec/client-server.md`, §4).
class FsError implements Exception {
  const FsError(this.path, this.kind, [this.cause]);

  final String path;
  final FsErrorKind kind;

  /// Что было причиной — исключение библиотеки или системы.
  ///
  /// Через границу не едет: у той стороны его типа может не быть вовсе.
  /// Наружу уходит [message], а причина остаётся в журнале той стороны, где
  /// случилась.
  final Object? cause;

  String get message => switch (kind) {
    FsErrorKind.notFound => 'Not found: $path',
    FsErrorKind.permissionDenied => 'Permission denied: $path',
    FsErrorKind.notADirectory => 'Not a directory: $path',
    FsErrorKind.alreadyExists => 'Already exists: $path',
    FsErrorKind.invalidName => 'Invalid name: $path',
    FsErrorKind.targetInsideSource => 'Cannot copy a directory into itself: $path',
    FsErrorKind.notSupported => 'Not supported: $path',
    FsErrorKind.unsupportedScheme => 'Protocol $path is not supported',
    FsErrorKind.invalidAddress => 'Wrong URI: $path',
    FsErrorKind.io => 'I/O error: $path',
  };

  @override
  String toString() => message;
}
