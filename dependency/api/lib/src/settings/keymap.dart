import '../serialization.dart';
import 'key_override.dart';

/// Набор клавиш: имя и переназначения (`docs/spec/keymaps.md`).
///
/// Опознаётся **именем**: его человек видит в списке и им выбирает.
/// Встроенные (mc, far, Finder) объявляют модули, свои складывает человек.
class Keymap implements Serializable {
  Keymap({this.name = '', List<KeyOverride>? keys}) : keys = [...?keys];

  String name;

  /// Переназначения — тем же списком, каким они живут в настройках.
  final List<KeyOverride> keys;

  /// Безымянный не выбрать.
  bool get isSane => name.isNotEmpty;

  @override
  void toMap(Map<String, dynamic> m) {
    m['name'] = name;
    m['keys'] = [for (final override in keys) serialize(override)];
  }

  /// Читает и прежний файл пресета: у него те же `name` и `keys`, а
  /// `settings` здесь не нужны и пропускаются.
  @override
  void fromMap(Map<String, dynamic> m) {
    name = extract(name, m['name']);
    keys
      ..clear()
      ..addAll(readKeyOverrides(m['keys']));
  }

  @override
  String toString() => 'Keymap($name: ${keys.length} keys)';
}

/// Переназначения из чего угодно, похожего на список.
///
/// Испорченная запись отбрасывается молча: она значит лишь, что одна клавиша
/// осталась умолчанием. Записи — любые словари: через границу изолятов они
/// приезжают `Map<dynamic, dynamic>`.
List<KeyOverride> readKeyOverrides(Object? stored) => [
  if (stored is List)
    for (final item in stored)
      if (extractObject(item, (_) => KeyOverride()) case final override? when override.isSane) override,
];
