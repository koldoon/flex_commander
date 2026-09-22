import '../serialization.dart';
import 'key_override.dart';

/// Набор выбора целиком: настройки всех модулей и клавиши
/// (`docs/spec/settings-presets.md`).
///
/// **Снимок выбора, а не файла настроек.** Что в него входит, решает схема
/// настроек: память — геометрия окна, пути панелей, история команд — в набор не
/// попадает вовсе, потому что её человек не выбирал.
///
/// Опознаётся **именем**: своего идентификатора у набора нет и заводить его
/// незачем — имя человек видит, им же и выбирает.
class Preset implements Serializable {
  Preset({this.name = '', Map<String, Map<String, Object?>>? settings, List<KeyOverride>? keys})
    : settings = {
        for (final entry in (settings ?? const {}).entries) entry.key: {...entry.value},
      },
      keys = [...?keys];

  String name;

  /// Модуль → поле → значение.
  ///
  /// Модуль назван **идентификатором** (`fc.terminal`), а не заголовком
  /// раздела: заголовок переводится и меняется от выпуска к выпуску, а
  /// идентификатор — нет.
  final Map<String, Map<String, Object?>> settings;

  /// Переназначенные клавиши — тем же списком, каким они живут в настройках.
  final List<KeyOverride> keys;

  /// Годится ли набор к делу: безымянный не выбрать.
  bool get isSane => name.isNotEmpty;

  /// Что стоит у этого поля в наборе; null — набор о нём молчит, и поле
  /// вернётся к умолчанию (`docs/spec/settings-presets.md`, §4).
  Object? valueOf(String module, String field) => settings[module]?[field];

  void put(String module, String field, Object? value) {
    (settings[module] ??= {})[field] = value;
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['name'] = name;
    m['settings'] = {
      for (final entry in settings.entries) entry.key: {...entry.value},
    };
    m['keys'] = [for (final override in keys) serialize(override)];
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    name = extract(name, m['name']);
    settings.clear();
    final stored = m['settings'];
    if (stored is Map) {
      for (final entry in stored.entries) {
        final fields = entry.value;
        if (fields is! Map) {
          continue;
        }
        settings['${entry.key}'] = {
          // Примитив или список строк — других значений у поля схемы не
          // бывает: флажок, число, строка, выбор и список
          // (`docs/spec/settings-editor.md`, §8). Чужое пропускается молча —
          // набор мог прийти из другого выпуска.
          for (final field in fields.entries)
            if (isPrimitive(field.value))
              '${field.key}': field.value
            else if (_isStrings(field.value))
              '${field.key}': [for (final item in field.value as List) '$item'],
        };
      }
    }
    keys.clear();
    final storedKeys = m['keys'];
    if (storedKeys is List) {
      for (final item in storedKeys) {
        // Испорченная запись отбрасывается молча: она означает лишь, что одна
        // клавиша осталась умолчанием.
        final override = extractObject(item, (_) => KeyOverride());
        if (override != null && override.isSane) {
          keys.add(override);
        }
      }
    }
  }

  @override
  String toString() => 'Preset($name: ${settings.length} sections, ${keys.length} keys)';
}

/// Список строк — значение поля-списка.
///
/// Разбирается здесь, а не полем: набор приходит файлом, и в нём на месте
/// списка может оказаться что угодно.
bool _isStrings(dynamic value) => value is List && value.every((item) => item is String);
