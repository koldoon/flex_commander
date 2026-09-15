import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обрезка пути слева: корень виден, хвост цел
/// (`docs/spec/panel-crumbs.md`, §2).
void main() {
  const style = TextStyle(fontSize: 14);
  const scaler = TextScaler.noScaling;

  double widthOf(String text) => textWidthOf(text, style, scaler);

  test('влезает — не трогаем', () {
    expect(trimTextHead('/home/docs', style, widthOf('/home/docs') + 1, scaler), '/home/docs');
  });

  test('режется по целым звеньям, а не по буквам', () {
    // Обрубок посреди имени читается как другое имя: глаз принимает его за
    // настоящее и только потом замечает многоточие.
    const path = '/Users/koldoon/Developer/Petrosoft/qwickserve/docs';
    final trimmed = trimTextHead(path, style, widthOf('/…/Petrosoft/qwickserve/docs') + 1, scaler);

    expect(trimmed, '/…/Petrosoft/qwickserve/docs');
  });

  test('одно звено не влезает — режем его буквами: хвост важнее правила', () {
    final trimmed = trimTextHead(
      '/Users/koldoon/невероятно-длинное-имя-каталога',
      style,
      widthOf('…-каталога'),
      scaler,
    );

    expect(trimmed, startsWith('…'));
    expect(trimmed, endsWith('каталога'));
  });

  test('не влезает — остаётся корень, многоточие и хвост', () {
    final trimmed = trimTextHead(
      '/Users/koldoon/Developer/qwickserve/dist',
      style,
      widthOf('/…/qwickserve/dist'),
      scaler,
    );

    expect(trimmed, startsWith('/…'), reason: 'по корню видно, о каком диске речь');
    expect(trimmed, endsWith('dist'), reason: 'в конце тот каталог, о котором речь');
  });

  test('у адреса корень — это машина', () {
    const address = 'ssh://koldoon@shark/home/koldoon/very/deep/place';
    final trimmed = trimTextHead(address, style, widthOf('ssh://koldoon@shark/…/deep/place'), scaler);

    // Разделитель после корня свой: `ssh://koldoon@shark/…/deep/place` читается
    // как адрес, а `ssh://koldoon@shark…` — как обрубок имени машины.
    expect(trimmed, startsWith('ssh://koldoon@shark/…/'));
    expect(trimmed, endsWith('place'));
  });

  test('корень сам не влезает — режем без него', () {
    // Иначе от строки осталось бы одно начало, а нужен конец.
    const address = 'ssh://koldoon@shark/home/koldoon';
    final trimmed = trimTextHead(address, style, widthOf('…koldoon'), scaler);

    expect(trimmed, startsWith('…'));
    expect(trimmed, isNot(startsWith('ssh')));
  });

  test('не путь — обрезается как раньше', () {
    final trimmed = trimTextHead('очень длинная подпись команды', style, widthOf('…команды'), scaler);

    expect(trimmed, startsWith('…'));
    expect(trimmed, endsWith('команды'));
  });

  test('обрезанное помещается в отведённое', () {
    const path = '/Users/koldoon/Developer/Petrosoft/Qwickserve Flex Applications/dist';
    for (final width in [40.0, 80.0, 160.0, 320.0]) {
      expect(widthOf(trimTextHead(path, style, width, scaler)), lessThanOrEqualTo(width), reason: 'ширина $width');
    }
  });

  group('поместилось ли', () {
    test('пустая строка помещается всегда', () {
      expect(textFits('', style, 0, scaler), isTrue);
    });

    test('вставшая впритык — поместилась', () {
      // Иначе подсказка висела бы на каждой ровно уложившейся строке и
      // повторяла бы видимое.
      const name = 'readme.md';
      expect(textFits(name, style, widthOf(name), scaler), isTrue);
    });

    test('не влезла на волос — не поместилась', () {
      const name = 'readme.md';
      expect(textFits(name, style, widthOf(name) - 1, scaler), isFalse);
    });

    test('память не врёт при смене стиля', () {
      const name = 'очень длинное имя файла';
      const bigger = TextStyle(fontSize: 28);

      final small = textWidthOf(name, style, scaler);
      final large = textWidthOf(name, bigger, scaler);

      expect(large, greaterThan(small), reason: 'стиль — часть вопроса, а не догадка');
      expect(textWidthOf(name, style, scaler), small, reason: 'повторный ответ тот же');
    });

    test('память не врёт при смене крупности', () {
      const name = 'имя файла';
      final plain = textWidthOf(name, style, scaler);
      final scaled = textWidthOf(name, style, const TextScaler.linear(2));

      expect(scaled, greaterThan(plain));
    });
  });
}
