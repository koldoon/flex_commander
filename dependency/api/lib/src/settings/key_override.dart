import '../serialization.dart';

/// Переназначенная клавиша: у какой привязки какая теперь
/// (`docs/spec/key-bindings.md`, §6).
///
/// **Привязка опознаётся именем — и только им.** Прежде опознавали парой
/// «команда и прежняя клавиша», и это имело бы смысл, будь у команды несколько
/// клавиш, из которых переписывают одну. Но клавиша у дела одна, а дел у
/// команды бывает несколько, и различать их прежней клавишей значило бы
/// объявлять клавишу именем.
///
/// Комбинация — строкой, той же, какой её разбирают (`KeyCombination.parse`) и
/// какой она записана в документации: `Alt-Cmd-C`. Порядок модификаторов в ней
/// закреплён, поэтому один и тот же выбор всегда даёт одну и ту же строку.
class KeyOverride implements Serializable {
  KeyOverride({this.binding = '', this.key = ''});

  /// Имя привязки (`KeyBinding.id`).
  String binding;

  /// Что стоит теперь; пусто — клавиши нет вовсе.
  String key;

  /// Годится ли запись к делу: без имени привязки целиться некуда.
  bool get isSane => binding.isNotEmpty;

  @override
  void toMap(Map<String, dynamic> m) {
    m['binding'] = binding;
    // Пустая строка пишется тоже: «клавиши нет» — это выбор человека, а не
    // отсутствие записи.
    m['key'] = key;
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    // Старая запись `{command, was, now}` читается как `{binding: command,
    // key: now}`: там, где у команды одно дело, это попадание в цель, а у
    // команды с несколькими делами прежнее переназначение отпадёт — честнее,
    // чем попасть не в то дело.
    binding = extract(binding, m.containsKey('binding') ? m['binding'] : m['command']);
    key = extract(key, m.containsKey('key') ? m['key'] : m['now']);
  }

  @override
  String toString() => '$binding: ${key.isEmpty ? '—' : key}';
}
