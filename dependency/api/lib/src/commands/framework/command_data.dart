/// Данные, которыми команды обмениваются внутри составной команды.
///
/// Результат каждого шага складывается сюда, а следующие шаги достают нужное
/// **по типу**: команда не знает, кто положил значение и было ли оно вообще, —
/// она просто просит то, с чем умеет работать. Так шаги остаются
/// самостоятельными и переставляются местами.
///
/// В референсе тип запрашивался объектом `Class` и разрешался отражением;
/// в Dart отражения нет, поэтому тип — параметр типа, а поиск идёт по `is`.
class CommandData {
  CommandData({CommandData? parent}) : _parent = parent;

  /// Данные окружения: у вложенной составной команды это данные родителя.
  final CommandData? _parent;

  final List<Object> _values = [];

  /// Обход уже идёт через эти данные.
  ///
  /// Составная команда отдаёт наружу свои данные, а их родитель — те самые
  /// данные, в которые она их и положила: цепочка замыкается сама на себя.
  /// Флаг разрывает круг — тот же приём, что в референсе (`inProgress`).
  bool _searching = false;

  /// Все значения этого уровня в порядке добавления.
  List<Object> get values => List.unmodifiable(_values);

  void add(Object value) => _values.add(value);

  void addAll(Iterable<Object> values) => _values.addAll(values);

  /// Последнее подходящее значение — или из родителя, если своего нет.
  ///
  /// Именно последнее: если два шага положили путь, дальше по цепочке нужен
  /// тот, что свежее. Вложенные [CommandData] раскрываются — составная команда
  /// отдаёт наружу свои данные одним значением.
  T? getObject<T extends Object>() {
    if (_searching) {
      return null;
    }
    _searching = true;
    try {
      return _lookup<T>();
    } finally {
      _searching = false;
    }
  }

  T? _lookup<T extends Object>() {
    for (var i = _values.length - 1; i >= 0; i--) {
      final value = _values[i];
      if (value is T) {
        return value;
      }
      if (value is CommandData) {
        final nested = value.getObject<T>();
        if (nested != null) {
          return nested;
        }
      }
    }
    return _parent?.getObject<T>();
  }

  /// Все подходящие значения в порядке добавления, снизу вверх по цепочке.
  List<T> getAllObjects<T extends Object>() {
    if (_searching) {
      return const [];
    }
    _searching = true;
    try {
      return _lookupAll<T>();
    } finally {
      _searching = false;
    }
  }

  List<T> _lookupAll<T extends Object>() {
    final results = <T>[];
    for (final value in _values) {
      if (value is CommandData) {
        results.addAll(value.getAllObjects<T>());
      } else if (value is T) {
        results.add(value);
      }
    }
    final parent = _parent;
    if (parent != null) {
      results.addAll(parent.getAllObjects<T>());
    }
    return results;
  }

  @override
  String toString() => 'CommandData(${_values.length} values)';
}
