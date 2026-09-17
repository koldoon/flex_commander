import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Правило имени: маска или выражение (`docs/spec/file-search.md`, §10.2).
void main() {
  group('маска', () {
    test('отбирает по образцу, как и везде', () {
      final rule = NameRule.parse('*.dart');

      expect(rule.matches('main.dart'), isTrue);
      expect(rule.matches('main.txt'), isFalse);
    });

    test('образцы через `;`, `!` исключает — движок тот же', () {
      final rule = NameRule.parse('*.dart;!*.g.dart');

      expect(rule.matches('app.dart'), isTrue);
      expect(rule.matches('app.g.dart'), isFalse);
    });

    test('регистр по просьбе', () {
      expect(NameRule.parse('*.DART').matches('main.dart'), isTrue, reason: 'по умолчанию всё равно');
      expect(NameRule.parse('*.DART', caseSensitive: true).matches('main.dart'), isFalse);
      expect(NameRule.parse('*.dart', caseSensitive: true).matches('main.dart'), isTrue);
    });

    test('пустая не подходит ничему и неверной не бывает', () {
      final rule = NameRule.parse('');

      expect(rule.isEmpty, isTrue);
      expect(rule.isValid, isTrue, reason: 'у маски собираться нечему');
      expect(rule.matches('main.dart'), isFalse);
    });
  });

  group('выражение', () {
    test('ищется внутри имени', () {
      final rule = NameRule.parse(r'\d+', regexp: true);

      expect(rule.matches('file42.txt'), isTrue);
      expect(rule.matches('file.txt'), isFalse);
    });

    test('`;` и `!` — часть выражения, а не разделители', () {
      // В маске это значило бы «два образца, второй исключающий».
      final rule = NameRule.parse('a;!b', regexp: true);

      expect(rule.matches('xa;!by'), isTrue, reason: 'совпало целиком, как написано');
      expect(rule.matches('a'), isFalse);
      expect(rule.matches('b'), isFalse);
    });

    test('регистр по просьбе', () {
      expect(NameRule.parse('MAIN', regexp: true).matches('main.dart'), isTrue);
      expect(NameRule.parse('MAIN', regexp: true, caseSensitive: true).matches('main.dart'), isFalse);
    });

    test('неверное не бросает, а опознаётся до обхода', () {
      final rule = NameRule.parse('*.dart', regexp: true);

      expect(rule.isValid, isFalse, reason: 'выражение не собралось');
      expect(rule.matches('main.dart'), isFalse, reason: 'и не подходит ничему');
    });

    test('пустое — это «не задано», а не «подходит всё»', () {
      final rule = NameRule.parse('   ', regexp: true);

      expect(rule.isEmpty, isTrue);
      expect(rule.isValid, isTrue, reason: 'пустое поле — не ошибка');
      expect(rule.matches('main.dart'), isFalse);
    });
  });

  test('набранное помнится как набрано', () {
    // По нему окно возвращает поле при `Again`, и оно же едет через границу.
    final rule = NameRule.parse('*.dart', caseSensitive: true);

    expect(rule.text, '*.dart');
    expect(rule.regexp, isFalse);
    expect(rule.caseSensitive, isTrue);
  });
}
