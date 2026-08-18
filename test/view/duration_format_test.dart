import 'package:flex_commander/view/format/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Оставшееся время в окне операции.
void main() {
  test('минуты и секунды всегда двузначные', () {
    expect(formatDuration(const Duration(seconds: 7)), '00:07');
    expect(formatDuration(const Duration(minutes: 7, seconds: 15)), '07:15');
  });

  test('часы печатаются, только когда они есть', () {
    // «00:07:15» на семь минут выглядит как ошибка.
    expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(formatDuration(const Duration(hours: 1, minutes: 23, seconds: 45)), '1:23:45');
  });

  test('доли секунды отбрасываются', () {
    expect(formatDuration(const Duration(milliseconds: 1500)), '00:01');
  });
}
