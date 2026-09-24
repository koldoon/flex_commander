import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Правило окраски: условие → цвет (`docs/spec/file-colors.md`).
void main() {
  // Скрытость `FileEntry` выводит из имени сам: точка в начале — и скрыт.
  FileEntry file(String name, {bool broken = false}) =>
      FileEntry(name: name, kind: EntryKind.file, path: '/home/$name', broken: broken);

  test('правило разбирается из записи настроек и уезжает обратно тем же', () {
    final rule = FileColorRule.fromJson({'mask': '*.bak', 'color': '#8a8a8a'})!;

    expect(rule.color, '#8a8a8a');
    expect(rule.when.matches(file('отчёт.bak')), isTrue);
    expect(rule.when.matches(file('отчёт.txt')), isFalse);
    expect(rule.toJson(), {'mask': '*.bak', 'color': '#8a8a8a'});
  });

  test('цвет ролью темы — законная запись', () {
    expect(FileColorRule.fromJson({'broken': true, 'color': 'error'})?.color, 'error');
  });

  test('запись без цвета и с непохожим на цвет выбрасывается', () {
    // Такое правило не покрасило бы ничего, но совпадало бы условием — и молча
    // перебивало бы следующее за ним.
    expect(FileColorRule.fromJson({'mask': '*.txt'}), isNull);
    expect(FileColorRule.fromJson({'mask': '*.txt', 'color': '#12'}), isNull);
    expect(FileColorRule.fromJson({'mask': '*.txt', 'color': 'серый как туман'}), isNull);
    expect(FileColorRule.fromJson('не карта'), isNull);
  });

  test('список разбирается целиком, а негодные записи пропадают', () {
    final rules = FileColorRule.listFromJson([
      {'hidden': true, 'color': 'secondaryText'},
      {'mask': '*.tmp'},
      {'mask': '*.o', 'color': '#333333'},
    ]);

    expect(rules.length, 2);
    expect(rules.first.when.matches(file('.ssh')), isTrue);
    expect(rules.last.color, '#333333');
  });

  test('условия складываются по «и»', () {
    final rule = FileColorRule.fromJson({'mask': '*.log', 'hidden': true, 'color': 'error'})!;

    expect(rule.when.matches(file('.tail.log')), isTrue);
    expect(rule.when.matches(file('tail.log')), isFalse, reason: 'скрытость не совпала');
  });
}
