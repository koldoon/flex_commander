import 'entry_condition.dart';

/// Правило: условие → каким цветом писать строку.
///
/// Список правил проверяется по порядку, **первое совпавшее выигрывает**.
/// Складывать цвета нельзя, а порядок — единственное понятное объяснение того,
/// почему файл покрашен именно так (`docs/spec/file-colors.md`).
///
/// Цвет здесь — **текст**: имя роли темы (`error`) или число (`#8a8a8a`). Во
/// что это превратить, решает тот, кто рисует: `fc_api` не знает ни про тему,
/// ни про цвета вовсе.
class FileColorRule {
  const FileColorRule({required this.when, required this.color});

  final EntryCondition when;

  /// Роль темы или `#RRGGBB` / `#AARRGGBB`.
  final String color;

  /// Похоже ли записанное на цвет.
  ///
  /// Проверяется **при разборе**, а не при рисовании: правило с опечаткой в
  /// цвете не красит ничего и его лучше выбросить сразу — иначе оно молча
  /// перебивало бы следующее за ним, совпадая условием и не давая цвета.
  static bool looksLikeColor(String value) => _number.hasMatch(value) || _role.hasMatch(value);

  static final RegExp _number = RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
  static final RegExp _role = RegExp(r'^[A-Za-z][A-Za-z0-9]*$');

  /// Разбор одного правила; null — правила не вышло, и его пропускают.
  ///
  /// Неразобранная запись не роняет приложение: файл настроек правят руками, а
  /// опечатка в нём не повод не показать каталог.
  static FileColorRule? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final map = json.cast<String, Object?>();
    final color = map['color'];
    if (color is! String) {
      return null;
    }
    final text = color.trim();
    return looksLikeColor(text) ? FileColorRule(when: EntryCondition.fromJson(map), color: text) : null;
  }

  /// Разбор списка правил: непонятные записи выбрасываются молча.
  static List<FileColorRule> listFromJson(Object? json) {
    if (json is! List) {
      return const [];
    }
    return [
      for (final item in json)
        if (fromJson(item) case final rule?) rule,
    ];
  }

  Map<String, Object?> toJson() => {...when.toJson(), 'color': color};
}
