import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSize', () {
    test('байты печатаются как есть', () {
      expect(formatSize(0), '0');
      expect(formatSize(126), '126');
      expect(formatSize(1023), '1023');
    });

    test('килобайты и мегабайты — как в макете', () {
      expect(formatSize(1024), '1K');
      expect(formatSize(6 * 1024), '6K');
      expect(formatSize(92262), '90.1K');
      expect(formatSize(15616819), '14.9M');
    });

    test('незначащий ноль не печатается', () {
      expect(formatSize(2 * 1024 * 1024), '2M');
    });

    test('округление переходит к следующей единице', () {
      // 1023.99K округлилось бы до 1024.0K — вместо этого показываем 1M.
      expect(formatSize(1024 * 1024 - 1), '1M');
    });

    test('неизвестный размер даёт пустую строку', () {
      expect(formatSize(-1), '');
    });
  });

  group('formatBytesLong', () {
    test('печатает единицу измерения', () {
      expect(formatBytesLong(914), '914 B');
      expect(formatBytesLong(1288490188), '1.2 GB');
    });
  });

  group('formatDate', () {
    test('формат макета: дд-мм-гггг', () {
      expect(formatDate(DateTime(2018, 2, 19)), '19-02-2018');
      expect(formatDate(DateTime(2026, 12, 1)), '01-12-2026');
    });

    test('пустая дата даёт пустую строку', () {
      expect(formatDate(null), '');
    });

    test('дата со временем', () {
      expect(formatDateTime(DateTime(2018, 2, 19, 14, 5)), '19-02-2018 14:05');
    });
  });
}
