import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подпись строки-цепочки: ступени обрезки
/// (`docs/spec/panel-view-compact-tree.md`, §6).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Тестовый шрифт: каждый знак шириной в кегль — десять точек на знак, и
  // ширины ниже считаются в уме.
  const style = TextStyle(fontSize: 10, fontFamily: 'FlutterTest');

  ({String head, String name, bool trimmed}) fit(double width, {FcTrimSide side = FcTrimSide.tail}) => fitChainName(
    head: 'src/main/java/com',
    name: 'acme',
    style: style,
    headStyle: style,
    maxWidth: width,
    scaler: TextScaler.noScaling,
    nameSide: side,
  );

  test('влезает — показывается целиком, без подсказки', () {
    final shown = fit(1000);

    expect('${shown.head}${shown.name}', 'src/main/java/com/acme');
    expect(shown.trimmed, isFalse);
  });

  test('не влезает — голова режется слева целыми звеньями', () {
    // «…/com/acme» — десять знаков, сто точек.
    final shown = fit(105);

    expect(shown.head, '…/com/');
    expect(shown.name, 'acme');
    expect(shown.trimmed, isTrue);
  });

  test('от головы может остаться одно многоточие', () {
    // «…/acme» — шесть знаков; «…/com/acme» уже не влезает.
    final shown = fit(65);

    expect(shown.head, '…/');
    expect(shown.name, 'acme');
  });

  test('не влезает и «…/имя» — остаётся одно имя', () {
    final shown = fit(45);

    expect(shown.head, isEmpty);
    expect(shown.name, 'acme');
    expect(shown.trimmed, isTrue);
  });

  test('одно имя режется так, как велит настройка обрезки имён', () {
    final shown = fit(30, side: FcTrimSide.middle);

    expect(shown.head, isEmpty);
    expect(shown.name, contains('…'), reason: 'середину режем сами');
  });
}
