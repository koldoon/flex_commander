import 'file_entry.dart';

/// Что работа сделала с одним объектом — **свершившееся**, а не задуманное.
///
/// Отмена идёт по этому списку снизу вверх: «отменить копирование» по списку
/// источников удалило бы чужое, а по журналу удаляется ровно то, что эта работа
/// создала (`docs/spec/operation-history.md`, §2).
///
/// Обычные значения: журнал едет через границу, и узлам там места нет. Путь —
/// **показываемый** (`FsNode.displayPath`, со всей цепочкой схем): только такую
/// строку можно разобрать заново.
sealed class JournalEntry {
  const JournalEntry();

  /// Запись словарём — для доводов работы отката.
  ///
  /// Через границу запись едет собой, как и `FileEntry`; словарь нужен там, где
  /// значения кладут в `OperationSpec.options`.
  Map<String, Object?> toMap();

  /// Разбор записи; null — запись не понята и пропускается.
  static JournalEntry? fromMap(Object? source) {
    if (source is! Map) {
      return null;
    }
    final map = source.cast<String, Object?>();
    final kind = _kindOf(map['kind']);
    final size = map['size'] is int ? map['size']! as int : FileEntry.unknownSize;
    final modified = map['modified'] is String ? DateTime.tryParse(map['modified']! as String) : null;

    return switch (map['what']) {
      'created' when map['path'] is String => Created(
        map['path']! as String,
        kind: kind,
        size: size,
        modified: modified,
        whole: map['whole'] == true,
      ),
      'moved' when map['from'] is String && map['to'] is String => Moved(
        from: map['from']! as String,
        to: map['to']! as String,
        kind: kind,
        size: size,
        modified: modified,
      ),
      'trashed' when map['from'] is String && map['to'] is String => Trashed(
        from: map['from']! as String,
        to: map['to']! as String,
        kind: kind,
        size: size,
        modified: modified,
      ),
      'destroyed' when map['path'] is String => Destroyed(
        map['path']! as String,
        reason: map['reason'] is String ? map['reason']! as String : '',
      ),
      _ => null,
    };
  }

  static EntryKind _kindOf(Object? name) {
    for (final kind in EntryKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return EntryKind.file;
  }
}

/// Объект появился там, где его не было: копия, распакованное, новый каталог.
///
/// [size] и [modified] — чтобы отмена не удалила молча то, что с тех пор
/// правили. `modified` пустой значит «неизвестно, сверяй по размеру»: платить
/// лишним чтением за каждый скопированный файл ради даты незачем.
class Created extends JournalEntry {
  const Created(this.path, {required this.kind, this.size = FileEntry.unknownSize, this.modified, this.whole = false});

  final String path;
  final EntryKind kind;
  final int size;
  final DateTime? modified;

  /// Каталог создан **целиком**: всё, что в нём, тоже сделала эта работа.
  ///
  /// Так пишется копия каталога, которого не было (`docs/spec/operation-history.md`,
  /// §6): отмена сносит его деревом. Пустой каталог, созданный `F7`, помечен
  /// иначе — его удаляют, только если он с тех пор так и остался пуст.
  final bool whole;

  bool get isDirectory => kind == EntryKind.directory;

  @override
  Map<String, Object?> toMap() => {
    'what': 'created',
    'path': path,
    'kind': kind.name,
    if (whole) 'whole': true,
    if (size != FileEntry.unknownSize) 'size': size,
    if (modified != null) 'modified': modified!.toIso8601String(),
  };
}

/// Объект уехал: переименование, перенос, распаковка «по месту».
class Moved extends JournalEntry {
  const Moved({
    required this.from,
    required this.to,
    required this.kind,
    this.size = FileEntry.unknownSize,
    this.modified,
  });

  final String from;
  final String to;
  final EntryKind kind;
  final int size;
  final DateTime? modified;

  @override
  Map<String, Object?> toMap() => {
    'what': 'moved',
    'from': from,
    'to': to,
    'kind': kind.name,
    if (size != FileEntry.unknownSize) 'size': size,
    if (modified != null) 'modified': modified!.toIso8601String(),
  };
}

/// Объект отправлен в корзину — и лёг там **под этим** именем.
///
/// Отдельно от [Moved] не ради отмены (она одинакова), а ради слов: «вернуть 3
/// из корзины» и «перенести 3 обратно» — разные вещи для того, кто читает
/// перечень перед откатом.
class Trashed extends JournalEntry {
  const Trashed({
    required this.from,
    required this.to,
    required this.kind,
    this.size = FileEntry.unknownSize,
    this.modified,
  });

  final String from;

  /// Путь в корзине: имя там разводится суффиксом при совпадении.
  final String to;

  final EntryKind kind;
  final int size;
  final DateTime? modified;

  @override
  Map<String, Object?> toMap() => {
    'what': 'trashed',
    'from': from,
    'to': to,
    'kind': kind.name,
    if (size != FileEntry.unknownSize) 'size': size,
    if (modified != null) 'modified': modified!.toIso8601String(),
  };
}

/// Сделано необратимо: перезапись, удаление мимо корзины.
///
/// Одна такая запись делает **всю** работу неотменимой: возвращать неоткуда, а
/// откатывать остальное поверх утраченного значило бы возвращать мир, которого
/// уже нет.
class Destroyed extends JournalEntry {
  const Destroyed(this.path, {required this.reason});

  final String path;

  /// Почему неотменимо — словами, для окна отмены.
  final String reason;

  @override
  Map<String, Object?> toMap() => {'what': 'destroyed', 'path': path, 'reason': reason};
}
