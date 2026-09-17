import 'file_mask.dart';

/// Правило имени: маска или регулярное выражение.
///
/// Одно значение вместо трёх полей запроса (текст, режим, регистр) — потому
/// что спрашивают у них одно: подходит ли имя. То же правило едет через
/// границу, показывается в заголовке окна находок и завтра понадобится
/// массовому переименованию (`docs/roadmap.md`, Е4).
///
/// Спецификация — `docs/spec/file-search.md`, §10.2.
class NameRule {
  NameRule._(this.text, this.regexp, this.caseSensitive, this._mask, this._pattern);

  /// Разобрать набранное. [regexp] — как читать: выражением или маской.
  ///
  /// **Неверное выражение не бросает**: правило просто получается негодным
  /// ([isValid] == false), и окно показывает ошибку у поля. Бросать здесь
  /// значило бы разбирать набранное на каждую букву внутри `try`.
  factory NameRule.parse(String text, {bool regexp = false, bool caseSensitive = false}) {
    if (!regexp) {
      return NameRule._(text, false, caseSensitive, FileMask.parse(text, caseSensitive: caseSensitive), null);
    }
    RegExp? pattern;
    try {
      // Пустое выражение не собираем вовсе: `RegExp('')` совпадает с чем
      // угодно, а пустое поле значит «не задано» — как и пустая маска.
      pattern = text.trim().isEmpty ? null : RegExp(text, caseSensitive: caseSensitive);
    } on FormatException {
      pattern = null;
    }
    return NameRule._(text, true, caseSensitive, null, pattern);
  }

  /// Правило, не подходящее ничему: пустой текст.
  static final NameRule none = NameRule.parse('');

  /// Что набрал человек — как набрал.
  ///
  /// Строкой, а не разобранным правилом: то же значение возвращается в поле
  /// при `Again`, уезжает через границу и пишется в заголовок находок, а
  /// `FileMask` и `RegExp` исходного текста не помнят.
  final String text;

  /// Читать выражением, а не маской.
  final bool regexp;

  final bool caseSensitive;

  final FileMask? _mask;
  final RegExp? _pattern;

  /// Задано ли правило вовсе. Пустое не подходит ничему — в том числе поэтому
  /// его и стоит отличать от `*`.
  bool get isEmpty => regexp ? _pattern == null : (_mask?.isEmpty ?? true);

  /// Собралось ли выражение. У маски собраться нечему: неверных масок не
  /// бывает, любая строка — это образец.
  bool get isValid => !regexp || text.trim().isEmpty || _pattern != null;

  /// Подходит ли имя.
  ///
  /// Маска сличается с именем целиком (`*.d` совпадёт и с каталогом `src.d`),
  /// выражение — **ищется внутри** имени: так его и ждут, а привязать к краям
  /// человек может сам (`^…$`).
  bool matches(String name) {
    if (regexp) {
      return _pattern?.hasMatch(name) ?? false;
    }
    return _mask?.matches(name) ?? false;
  }

  @override
  String toString() => 'NameRule(${regexp ? 'выражение' : 'маска'}: "$text"${caseSensitive ? ', регистр' : ''})';
}
