import '../serialization.dart';

/// Настройки одного модуля.
///
/// Модуль не знает ни где лежит файл настроек, ни что в нём ещё есть: он
/// работает со своим разделом и просит его сохранить. Раздел именуется
/// идентификатором модуля, поэтому переживает и перезапуск, и отключение
/// самого модуля.
abstract interface class SettingsScope {
  /// Типизированный раздел настроек.
  ///
  /// Умолчания задаёт [create] — прочитанное из файла дописывается в готовый
  /// объект, поэтому испорченное или отсутствующее значение остаётся
  /// умолчанием. Повторный вызов отдаёт тот же экземпляр: раздел — это
  /// состояние модуля, а не его копия.
  T section<T extends Serializable>(T Function() create);

  /// Просит ядро сохранить настройки.
  ///
  /// Запись отложенная — как и у остальных настроек: подряд идущие изменения
  /// сливаются в одну.
  void save();
}

/// Разделы настроек всех модулей — то, что лежит в файле под ключом `modules`.
///
/// **Незнакомое не теряется.** Раздел, который в этом запуске никто не
/// разбирал, записывается обратно как есть: отключённый модуль не должен
/// терять свои настройки только потому, что его сегодня не включили.
class ModuleSettings implements Serializable {
  /// Разобранные разделы: пространство имён → объект модуля.
  final Map<String, Serializable> _sections = {};

  /// Сырые разделы из файла: пространство имён → его содержимое.
  final Map<String, Map<String, dynamic>> _raw = {};

  /// Что делать, когда модуль просит сохранить свои настройки.
  void Function()? onSave;

  /// Раздел модуля с этим именем.
  SettingsScope scope(String namespace) => _Scope(this, namespace);

  /// Пространства имён, о которых что-то известно.
  Iterable<String> get namespaces => {..._raw.keys, ..._sections.keys};

  T _section<T extends Serializable>(String namespace, T Function() create) {
    final existing = _sections[namespace];
    if (existing is T) {
      return existing;
    }

    final section = create();
    final stored = _raw[namespace];
    if (stored != null) {
      section.fromMap(stored);
    }
    _sections[namespace] = section;
    return section;
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    _raw.clear();
    for (final entry in m.entries) {
      final value = entry.value;
      // Любой словарь, а не только `Map<String, dynamic>`: из файла разделы
      // приходят разобранным JSON, а через границу — своей же сериализацией, и
      // та отдаёт `Map<dynamic, dynamic>`. Проверка на точный тип молча теряла
      // бы половину случаев — и потеряла: разделы не доехали до экрана вовсе.
      if (value is Map) {
        _raw[entry.key] = value.map((key, item) => MapEntry('$key', item));
      }
    }

    // Уже разобранные разделы дочитываются из нового содержимого: так
    // настройки можно перечитать, не пересоздавая модули.
    for (final entry in _sections.entries) {
      final stored = _raw[entry.key];
      if (stored != null) {
        entry.value.fromMap(stored);
      }
    }
  }

  @override
  void toMap(Map<String, dynamic> m) {
    // Сперва нетронутое — чтобы разобранное перекрыло его свежими значениями.
    m.addAll(_raw);
    for (final entry in _sections.entries) {
      m[entry.key] = serialize(entry.value);
    }
  }
}

class _Scope implements SettingsScope {
  const _Scope(this._settings, this._namespace);

  final ModuleSettings _settings;
  final String _namespace;

  @override
  T section<T extends Serializable>(T Function() create) => _settings._section(_namespace, create);

  @override
  void save() => _settings.onSave?.call();
}
