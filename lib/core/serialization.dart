/// Common serializable classes interface
abstract class Serializable {
  void fromMap(Map<String, dynamic> m);
  void toMap(Map<String, dynamic> m);
}

T extract<T>(T value, dynamic source) {
  var t = T.toString();
  final nullable = t.endsWith('?');
  if (nullable && source == null) return null as T;
  if (nullable) t = t.substring(0, t.length - 1);
  if (value == null) {
    if (t == 'bool') return toBool(source) as T;
    if (t == 'String') return toString(source) as T;
    if (t == 'int') return toInt(source) as T;
    if (t == 'double') return toDouble(source) as T;
    if (t == 'num') return toNumber(source) as T;
    if (t == 'DateTime') return toDateTime(source) as T;
  } else {
    if (t == 'bool') return toBool(source, value as bool) as T;
    if (t == 'String') return toString(source, value as String) as T;
    if (t == 'int') return toInt(source, value as int) as T;
    if (t == 'double') return toDouble(source, value as double) as T;
    if (t == 'num') return toNumber(source, value as num) as T;
    if (t == 'DateTime') return toDateTime(source, value as DateTime) as T;
    if (value is Serializable) {
      if (source != null && source is Map<String, dynamic>) {
        value.fromMap(source);
      }
      return value;
    }
  }
  throw ArgumentError('extract: Unsupported conversion type ${T.toString()}');
}

/// ---------------------------------------------------------------------------

typedef ItemInstanceFactory<T> = T Function(dynamic item);

/// Extract typed items List from dynamic source.
/// [source] Any source that looks like a List
/// [factory] Function that returns List item instance (Serializable)
List<T> extractList<T>(dynamic source, [ItemInstanceFactory<T>? factory]) {
  if (source == null || source is! List) {
    return List<T>.of([]);
  }
  final list = List.castFrom(source);
  late final Iterable<T> items;
  if (factory != null) {
    items = list.map((e) => extract<T>(factory(e), e));
  } else {
    final defaultValue = _getDefaultValue<T>();
    items = list.map((e) => extract<T>(defaultValue, e));
  }
  return items.toList();
}

/// Extract a nullable nested [Serializable] object from a dynamic [source].
/// Returns `null` when [source] is not a map, otherwise builds an instance via
/// [factory] and populates it from the map.
/// [source] Any source that looks like a Map
/// [factory] Function that returns the item instance (Serializable)
T? extractObject<T extends Serializable>(dynamic source, ItemInstanceFactory<T> factory) {
  if (source is! Map) return null;
  final map = Map<String, dynamic>.from(source);
  return factory(map)..fromMap(map);
}

dynamic _getDefaultValue<T>() {
  var t = T.toString();
  if (t.endsWith('?')) t = t.substring(0, t.length - 1);
  if (t == 'bool') return false;
  if (t == 'String') return '';
  if (t == 'num' || T == int) return 0;
  if (t == 'double') return 0.0;
  if (t == 'DateTime') return null;
  throw ArgumentError('Unable to get default value for type ${T.toString()}');
}

/// ---------------------------------------------------------------------------

dynamic serialize(dynamic obj) {
  if (obj is Iterable) {
    return obj.toList().map((e) => serialize(e)).toList();
  } else if (obj is Map) {
    return Map.fromEntries(Map.castFrom(obj).entries.map((e) => MapEntry(e.key, serialize(e.value))));
  } else if (obj is DateTime) {
    return obj.toIso8601String();
  } else if (isPrimitive(obj)) {
    return obj;
  } else if (obj is Serializable) {
    final map = <String, dynamic>{};
    obj.toMap(map);
    map.forEach((key, value) => map.update(key, (value) => serialize(value)));
    return map;
  } else {
    throw ArgumentError('serialize(): Type is not supported: ${obj.runtimeType}');
  }
}

List<Map<String, dynamic>> serializeList<T extends Serializable>(List<T> list) {
  return list.map((item) {
    final m = <String, dynamic>{};
    item.toMap(m);
    return m;
  }).toList();
}

/// ---------------------------------------------------------------------------

bool toBool(dynamic value, [bool defaultValue = false]) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value > 0.0;
  if (value is String) {
    final val = value.toLowerCase();
    if (val == 'true' || val == 'false') return val == 'true';
    if (val == 'yes' || val == 'no') return val == 'yes';
    if (val == 'y' || val == 'n') return val == 'y';
    final maybeNumber = num.tryParse(value);
    if (maybeNumber != null) return maybeNumber != 0;
    return defaultValue;
  }
  throw ArgumentError('toBool: Unsupported serialisation type ${value.runtimeType.toString()}');
}

num toNumber(dynamic value, [num defaultValue = 0]) {
  if (value == null) return defaultValue;
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? defaultValue;
  if (value is bool) return value == true ? 1 : 0;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  throw ArgumentError('toNumber: Unsupported serialisation type ${value.runtimeType.toString()}');
}

int toInt(dynamic value, [int defaultValue = 0]) {
  if (value == null) return defaultValue;
  if (value is num) return value.toInt();
  if (value is String) return num.tryParse(value)?.toInt() ?? defaultValue;
  if (value is bool) return value == true ? 1 : 0;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  throw ArgumentError('toInt: Unsupported serialisation type ${value.runtimeType.toString()}');
}

double toDouble(dynamic value, [double defaultValue = 0]) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  if (value is String) return num.tryParse(value)?.toDouble() ?? defaultValue;
  if (value is bool) return value == true ? 1.0 : 0.0;
  if (value is DateTime) return value.millisecondsSinceEpoch.toDouble();
  throw ArgumentError('toDouble: Unsupported serialisation type ${value.runtimeType.toString()}');
}

String toString(dynamic value, [String defaultValue = '']) {
  if (value == null) return defaultValue;
  if (value is String) return value;
  if (value is num) return value.toString();
  if (value is bool) return value ? 'true' : 'false';
  if (value is DateTime) return value.toIso8601String();
  throw ArgumentError('toString: Unsupported serialisation type ${value.runtimeType.toString()}');
}

String toYesNo(dynamic value, [bool defaultValue = false]) {
  final b = toBool(value, defaultValue);
  return b ? 'yes' : 'no';
}

final _usaDate = RegExp(r'^[0-9]{2}/[0-9]{2}/[0-9]{4}$');
final _shortUsaDate = RegExp(r'^[0-9]{2}/[0-9]{2}/[0-9]{2}$');

DateTime? toDateTime(dynamic value, [DateTime? defaultValue]) {
  if (value == null) return defaultValue;
  if (value is DateTime) return value;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is bool) return defaultValue;
  if (value is String) {
    final val = value.trim();
    final maybeNumber = num.tryParse(val)?.toInt();
    if (maybeNumber != null) {
      return DateTime.fromMillisecondsSinceEpoch(maybeNumber);
    }
    final maybeDateInUsaFormat = _usaDate.hasMatch(val);
    if (maybeDateInUsaFormat) {
      final parts = val.split('/');
      return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
    }
    final maybeDateInShortUsaFormat = _shortUsaDate.hasMatch(val);
    if (maybeDateInShortUsaFormat) {
      final parts = val.split('/');
      return DateTime(int.parse('20${parts[2]}'), int.parse(parts[0]), int.parse(parts[1]));
    }
    return DateTime.tryParse(val) ?? defaultValue;
  }
  throw ArgumentError('toDateTime: Unsupported serialisation type ${value.runtimeType.toString()}');
}

bool isPrimitive(dynamic value) {
  return value is bool || value is String || value is num || value == null;
}
