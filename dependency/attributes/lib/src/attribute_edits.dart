/// Кому достанется правка внутри каталога.
///
/// Действует только при [AttributeEdits.recursive]: сами названные объекты
/// правятся всегда, а отбор относится к тому, что нашлось внутри.
enum AttributeScope {
  /// Всё подряд.
  all,

  /// Только файлы: `755`, применённый ко всему дереву, иначе делает исполняемым
  /// каждый текстовый файл. Ровно затем в `chmod` и есть `X`.
  files,

  /// Только каталоги.
  directories;

  static AttributeScope byName(String? name) =>
      AttributeScope.values.where((scope) => scope.name == name).firstOrNull ?? AttributeScope.all;
}

/// Имена работы и её доводов — язык границы.
///
/// Заявку собирает команда на одной стороне, а исполняет работа на другой;
/// общее у них ровно эти имена.
abstract final class AttributeOperations {
  static const String apply = 'attrs.apply';

  static const String setBits = 'setBits';
  static const String clearBits = 'clearBits';
  static const String modified = 'modified';
  static const String accessed = 'accessed';
  static const String uid = 'uid';
  static const String gid = 'gid';
  static const String owner = 'owner';
  static const String group = 'group';
  static const String xattrSet = 'xattrSet';
  static const String xattrRemove = 'xattrRemove';
  static const String recursive = 'recursive';
  static const String applyTo = 'applyTo';
}

/// Что человек поменял в окне — и ничего сверх того.
///
/// **Режим едет парой масок, а не готовым числом.** Целей бывает несколько, и
/// права у них разные: послать готовый режим значило бы выровнять по нему все
/// объекты сразу — человек поднял `w` у группы, а заодно молча снял `x` у того
/// файла, где он был. Бит, которого нет ни в одной маске, у каждого объекта
/// остаётся своим:
///
/// ```
/// mode' = (mode | setBits) & ~clearBits
/// ```
///
/// Это и есть «смешанное» состояние флажка, выраженное данными, а не признаком
/// в окне: флажок, которого не трогали, просто не попадает в маски.
class AttributeEdits {
  const AttributeEdits({
    this.setBits = 0,
    this.clearBits = 0,
    this.modified,
    this.accessed,
    this.uid,
    this.gid,
    this.owner = '',
    this.group = '',
    this.xattrSet = const {},
    this.xattrRemove = const [],
    this.recursive = false,
    this.applyTo = AttributeScope.all,
  });

  /// Все двенадцать битов режима: девять прав плюс `setuid`, `setgid`, sticky.
  static const int modeMask = 0xFFF;

  /// Какие биты режима поднять.
  final int setBits;

  /// Какие опустить.
  final int clearBits;

  /// Даты; null — не трогать эту.
  final DateTime? modified;
  final DateTime? accessed;

  /// Числа владельца и группы; null — не трогать.
  final int? uid;
  final int? gid;

  /// Они же именами — когда в поле набрали не число.
  ///
  /// Разрешает имя в число **работа**: словарь пользователей живёт у источника
  /// ([UserDirectory]), а по эту сторону границы его нет. Одновременно число и
  /// имя не приходят никогда — окно шлёт что-то одно.
  final String owner;
  final String group;

  /// Расширенные атрибуты: имя → байты.
  final Map<String, List<int>> xattrSet;

  /// Какие расширенные атрибуты убрать.
  final List<String> xattrRemove;

  /// Идти ли внутрь каталогов. Умолчание осторожное: не спросив, внутрь не
  /// идём — правка дерева необратима.
  final bool recursive;

  final AttributeScope applyTo;

  /// Менять нечего: окно открыли и закрыли, ничего не тронув.
  ///
  /// Работу с пустой правкой всё равно можно завести — она честно ничего не
  /// сделает, — но заводить её незачем.
  bool get isEmpty =>
      setBits == 0 &&
      clearBits == 0 &&
      modified == null &&
      accessed == null &&
      uid == null &&
      gid == null &&
      owner.isEmpty &&
      group.isEmpty &&
      xattrSet.isEmpty &&
      xattrRemove.isEmpty;

  /// Новый режим объекта по его нынешнему.
  ///
  /// Тип объекта из старших битов сохраняется: в масках живут только права.
  int applyToMode(int mode) => (mode | (setBits & modeMask)) & ~(clearBits & modeMask);

  /// Достанется ли правка объекту такого вида.
  bool reaches({required bool isDirectory}) => switch (applyTo) {
    AttributeScope.all => true,
    AttributeScope.files => !isDirectory,
    AttributeScope.directories => isDirectory,
  };

  /// Доводы работы — обычными значениями: через границу живое не ходит.
  ///
  /// Даты уезжают миллисекундами эпохи, а не `DateTime`: у той стороны свой
  /// часовой пояс, и число однозначно.
  Map<String, Object?> toOptions() => {
    if (setBits != 0) AttributeOperations.setBits: setBits,
    if (clearBits != 0) AttributeOperations.clearBits: clearBits,
    if (modified != null) AttributeOperations.modified: modified!.millisecondsSinceEpoch,
    if (accessed != null) AttributeOperations.accessed: accessed!.millisecondsSinceEpoch,
    if (uid != null) AttributeOperations.uid: uid,
    if (gid != null) AttributeOperations.gid: gid,
    if (owner.isNotEmpty) AttributeOperations.owner: owner,
    if (group.isNotEmpty) AttributeOperations.group: group,
    if (xattrSet.isNotEmpty) AttributeOperations.xattrSet: {for (final one in xattrSet.entries) one.key: one.value},
    if (xattrRemove.isNotEmpty) AttributeOperations.xattrRemove: [...xattrRemove],
    if (recursive) AttributeOperations.recursive: true,
    if (applyTo != AttributeScope.all) AttributeOperations.applyTo: applyTo.name,
  };

  /// Обратно — на той стороне границы.
  ///
  /// Чужое и негодное пропускается, а не роняет работу: доводы приезжают
  /// картой, и заявку может собрать кто угодно.
  factory AttributeEdits.fromOptions(Map<String, Object?> options) {
    T? value<T>(String name) {
      final one = options[name];
      return one is T ? one : null;
    }

    DateTime? time(String name) {
      final millis = value<int>(name);
      return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
    }

    final set = value<Map<Object?, Object?>>(AttributeOperations.xattrSet) ?? const {};
    final remove = value<List<Object?>>(AttributeOperations.xattrRemove) ?? const [];

    return AttributeEdits(
      setBits: value<int>(AttributeOperations.setBits) ?? 0,
      clearBits: value<int>(AttributeOperations.clearBits) ?? 0,
      modified: time(AttributeOperations.modified),
      accessed: time(AttributeOperations.accessed),
      uid: value<int>(AttributeOperations.uid),
      gid: value<int>(AttributeOperations.gid),
      owner: value<String>(AttributeOperations.owner) ?? '',
      group: value<String>(AttributeOperations.group) ?? '',
      xattrSet: {
        for (final one in set.entries)
          if (one.key is String && one.value is List<int>) one.key! as String: one.value! as List<int>,
      },
      xattrRemove: [
        for (final one in remove)
          if (one is String) one,
      ],
      recursive: value<bool>(AttributeOperations.recursive) ?? false,
      applyTo: AttributeScope.byName(value<String>(AttributeOperations.applyTo)),
    );
  }
}
