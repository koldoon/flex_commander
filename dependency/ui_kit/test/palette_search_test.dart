import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отбор палитры: буквы запроса ищутся по порядку, но не подряд.
void main() {
  PaletteMatch? match(String query, String label, {String owner = 'Module'}) =>
      matchCommand(query, label: label, owner: owner);

  /// Порядок, в котором палитра покажет эти названия по этому запросу.
  List<String> order(String query, List<(String, String)> commands) {
    final found = [
      for (final (label, owner) in commands)
        if (match(query, label, owner: owner) case final result?) (label, result),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (label, _) in found) label];
  }

  test('буквы ищутся по порядку и не обязательно подряд', () {
    expect(match('cpf', 'Copy File'), isNotNull);
    expect(match('cf', 'Copy File'), isNotNull);
    // Порядок важен: `fc` в `Copy File` найтись не должно.
    expect(match('fcopy', 'Copy File'), isNull);
    expect(match('xyz', 'Copy File'), isNull);
  });

  test('регистр не важен', () {
    expect(match('COPY', 'Copy File'), isNotNull);
    expect(match('copy', 'COPY FILE'), isNotNull);
  });

  test('с начала слова весит больше, чем из середины', () {
    final atStart = match('set', 'Settings')!;
    final inside = match('set', 'Reset')!;

    expect(atStart.score, greaterThan(inside.score));
  });

  test('подряд весит больше, чем вразбивку', () {
    final together = match('opy', 'Copy')!;
    final apart = match('opy', 'Order picked yesterday')!;

    expect(together.score, greaterThan(apart.score));
  });

  test('при равном весе выигрывает короткое название', () {
    expect(order('copy', [('Copy path to clipboard', 'M'), ('Copy', 'M')]), ['Copy', 'Copy path to clipboard']);
  });

  test('ищется и по модулю, но весит меньше', () {
    final byOwner = match('term', 'Toggle typing', owner: 'Terminal')!;
    final byLabel = match('term', 'Terminal session', owner: 'Shell')!;

    expect(byOwner.ownerHits, isNotEmpty);
    expect(byOwner.labelHits, isEmpty);
    expect(byLabel.score, greaterThan(byOwner.score), reason: 'название ближе к делу, чем то, кем команда принесена');
  });

  test('совпавшие буквы известны — их подсвечивают', () {
    final found = match('cf', 'Copy File')!;

    expect(found.labelHits, [0, 5]);
  });

  test('пустой запрос подходит всему: палитра остаётся каталогом', () {
    expect(match('', 'Copy File'), isNotNull);
    expect(match('   ', 'Copy File')!.labelHits, isEmpty);
  });
}
