import 'dart:convert';

/// Один расширенный атрибут: имя и байты.
///
/// Байты, а не строка: значением бывает что угодно, и `com.apple.FinderInfo` —
/// это ровно тридцать два двоичных байта, среди которых нули. Возить такое
/// текстом значит его испортить.
class Xattr {
  const Xattr(this.name, this.value);

  final String name;
  final List<int> value;

  /// Значение, которое можно показать и править строкой; null — двоичное.
  ///
  /// Показывать двоичное как строку нельзя: человек увидел бы кашу, а сохранив
  /// её обратно — стёр бы то, что там было. Поэтому вопрос задан здесь, рядом
  /// со значением, а не в окне: ответ у него один на всех, кто спросит.
  String? get text {
    if (value.isEmpty) {
      return '';
    }
    try {
      final decoded = utf8.decode(value);
      // Управляющие символы — верный признак того, что это не текст, даже
      // когда байты случайно сложились в правильный UTF-8.
      return decoded.runes.any((rune) => rune < 0x20 && rune != 0x09) ? null : decoded;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'Xattr($name)';
}

/// Всё, что можно править у объекта, — прочитанное **сейчас**.
///
/// Не то же, что [FileAttributes] в строке списка: там режим с последнего
/// чтения каталога, и править по нему значило бы вернуть файлу права, которых
/// у него уже нет. Та же причина, по которой перенос режима при записи файла
/// читает его у самого объекта.
///
/// Собирается из трёх источников — атрибуты, расширенные атрибуты и словарь
/// пользователей, — и складывает их ядро: провайдер отвечает только за свою
/// часть (`docs/spec/file-attributes.md`, §3.4).
class NodeAttributes {
  const NodeAttributes({
    this.mode = 0,
    this.modeString = '',
    this.uid,
    this.gid,
    this.owner = '',
    this.group = '',
    this.modified,
    this.accessed,
    this.xattrs = const [],
    this.canEditMode = false,
    this.canEditTimes = false,
    this.canEditOwner = false,
    this.canEditXattrs = false,
  });

  /// Источник не сказал о себе ничего: править нечего, и окно это покажет.
  static const NodeAttributes unknown = NodeAttributes();

  /// Режим целиком, вместе с типом объекта; 0 — режима у источника нет вовсе.
  final int mode;

  /// Он же строкой — `-rw-r--r--`.
  final String modeString;

  /// Числа владельца и группы; null — источник их не знает.
  final int? uid;
  final int? gid;

  /// Имена владельца и группы; пусто — источник имён не знает, и показывается
  /// число.
  final String owner;
  final String group;

  final DateTime? modified;
  final DateTime? accessed;

  final List<Xattr> xattrs;

  /// Что из этого источник даст поменять.
  ///
  /// Значениями, а не вопросом к источнику: на экранной стороне провайдера нет
  /// вовсе, а окно обязано погасить поля **до** того, как человек в них
  /// наберёт.
  final bool canEditMode;
  final bool canEditTimes;
  final bool canEditOwner;
  final bool canEditXattrs;

  /// Права из режима — девять символов без типа объекта.
  int get permissions => mode & 0xFFF;

  /// То же значение с именами владельца и группы.
  NodeAttributes withNames({required String owner, required String group}) => _copy(owner: owner, group: group);

  /// То же значение с расширенными атрибутами; их приносит другое умение.
  NodeAttributes withXattrs(List<Xattr> xattrs) => _copy(xattrs: xattrs, canEditXattrs: true);

  NodeAttributes _copy({String? owner, String? group, List<Xattr>? xattrs, bool? canEditXattrs}) => NodeAttributes(
    mode: mode,
    modeString: modeString,
    uid: uid,
    gid: gid,
    owner: owner ?? this.owner,
    group: group ?? this.group,
    modified: modified,
    accessed: accessed,
    xattrs: xattrs ?? this.xattrs,
    canEditMode: canEditMode,
    canEditTimes: canEditTimes,
    canEditOwner: canEditOwner,
    canEditXattrs: canEditXattrs ?? this.canEditXattrs,
  );

  @override
  String toString() => 'NodeAttributes($modeString, ${xattrs.length} xattr)';
}
