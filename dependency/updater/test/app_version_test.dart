import 'package:fc_updater/fc_updater.dart';
import 'package:flutter_test/flutter_test.dart';

/// Версия сборки и её старшинство (`docs/spec/self-update.md`, §4).
void main() {
  AppVersion v(String text) => AppVersion.parse(text)!;

  test('разбирается тег, голая версия и версия с номером сборки', () {
    expect(v('v0.0.72'), const AppVersion(0, 0, 72));
    expect(v('0.0.72'), const AppVersion(0, 0, 72));
    expect(v('0.0.72+128'), const AppVersion(0, 0, 72), reason: 'номер сборки к старшинству не относится');
    expect(v('1.0'), const AppVersion(1, 0, 0), reason: 'недостающее звено — ноль');
  });

  test('десятый выпуск старше девятого', () {
    // По алфавиту наоборот, и ошибка эта тихая: обновление просто перестало бы
    // предлагаться.
    expect(v('0.0.10') > v('0.0.9'), isTrue);
    expect(v('0.1.0') > v('0.0.99'), isTrue);
    expect(v('1.0.0') > v('0.9.9'), isTrue);
  });

  test('одинаковые версии равны и друг друга не старше', () {
    expect(v('0.0.72'), v('v0.0.72'));
    expect(v('0.0.72') > v('0.0.72'), isFalse);
    expect(v('0.0.72') < v('0.0.72'), isFalse);
  });

  test('сборка с машины разработчика новее любого выпуска', () {
    // `1.0.0` из `pubspec.yaml` — то, что стоит в отладочной сборке. Так она
    // сама себя и не обновляет.
    expect(v('1.0.0') > v('0.0.72'), isTrue);
  });

  test('что не версия — то не версия', () {
    expect(AppVersion.parse('beta'), isNull);
    expect(AppVersion.parse('0.0.1-beta'), isNull, reason: 'предвыпуски мы не берём вовсе');
    expect(AppVersion.parse(''), isNull);
    expect(AppVersion.parse('1.2.3.4'), isNull);
    expect(AppVersion.parse('-1.0.0'), isNull);
  });
}
