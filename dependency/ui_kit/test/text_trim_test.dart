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

    expect(trimmed, startsWith('ssh://koldoon@shark…'));
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
}
