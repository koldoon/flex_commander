import 'package:fc_search/fc_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор полей размера и даты (`docs/spec/file-search.md`, §10.5).
void main() {
  group('размер', () {
    test('число и суффиксы по 1024', () {
      expect(SearchLimits.parseSize('100'), 100);
      expect(SearchLimits.parseSize('500k'), 500 * 1024);
      expect(SearchLimits.parseSize('2M'), 2 * 1024 * 1024);
      expect(SearchLimits.parseSize('1G'), 1024 * 1024 * 1024);
      expect(SearchLimits.parseSize(' 2 MB '), 2 * 1024 * 1024, reason: 'пробелы и `b` не мешают');
    });

    test('пустое — это «без ограничения», а мусор — ошибка', () {
      expect(SearchLimits.parseSize('  '), isNull);
      expect(SearchLimits.parseSize('много'), isNull);
      expect(SearchLimits.parseSize('2 мегабайта'), isNull);
    });
  });

  group('дата', () {
    final now = DateTime(2026, 9, 17, 12);

    test('дата целиком', () {
      expect(SearchLimits.parseTime('2026-09-01'), DateTime(2026, 9, 1));
    });

    test('относительный возраст считается от сейчас', () {
      expect(SearchLimits.parseTime('7d', now: now), DateTime(2026, 9, 10, 12));
      expect(SearchLimits.parseTime('2w', now: now), DateTime(2026, 9, 3, 12));
      expect(SearchLimits.parseTime('3m', now: now), DateTime(2026, 6, 17, 12), reason: 'календарём, а не сутками');
      expect(SearchLimits.parseTime('1y', now: now), DateTime(2025, 9, 17, 12));
    });

    test('несуществующая дата — опечатка, а не соседний месяц', () {
      // `DateTime` переносит лишнее молча: 31 февраля станет 3 марта.
      expect(SearchLimits.parseTime('2026-02-31'), isNull);
      expect(SearchLimits.parseTime('2026-13-01'), isNull);
      expect(SearchLimits.parseTime('01.09.2026'), isNull);
    });
  });

  test('годность спрашивают у всех полей разом', () {
    expect(const SearchLimits().isValid, isTrue, reason: 'пустое — не ошибка');
    expect(const SearchLimits(sizeFromText: '2M', beforeText: '2026-01-01').isValid, isTrue);
    expect(const SearchLimits(sizeToText: 'много').isValid, isFalse);
    expect(const SearchLimits(afterText: 'вчера').isValid, isFalse);
  });
}
