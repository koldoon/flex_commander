import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Форматы вывода колонок (`docs/spec/column-formats.md`).
void main() {
  group('размер', () {
    test('авто — как было: сокращение по 1024', () {
      expect(formatSize(126), '126');
      expect(formatSize(6144), '6.0K');
      expect(formatSize(15_623_781), '14.9M');
    });

    test('байты — до последнего, с разбивкой по тысячам', () {
      expect(formatSize(6144, SizeFormat.bytes), '6 144');
      expect(formatSize(126, SizeFormat.bytes), '126');
    });

    test('двоичные и десятичные считают по-разному и зовутся по-разному', () {
      // Единица, названная одинаково при разном основании, — обман: 6144 байт
      // это 6.0 KB, но 6.1 kB.
      // Пробел между числом и единицей неразрывный: это одно целое.
      expect(formatSize(6144, SizeFormat.binary), '6.0\u00a0KB');
      expect(formatSize(6144, SizeFormat.decimal), '6.1\u00a0kB');
      expect(formatSize(1_000_000, SizeFormat.decimal), '1.0\u00a0MB');
    });

    test('неизвестный размер пуст в любом формате', () {
      for (final format in SizeFormat.values) {
        expect(formatSize(-1, format), '', reason: format.id);
      }
    });

    test('незнакомое имя формата — это умолчание', () {
      expect(SizeFormat.byId('такого-нет'), SizeFormat.auto);
      expect(SizeFormat.byId(''), SizeFormat.auto);
    });
  });

  group('дата', () {
    final moment = DateTime(2018, 2, 19, 14, 5);

    test('четыре вида, и все про одно и то же мгновение', () {
      expect(formatDate(moment), '19-02-2018');
      expect(formatDate(moment, DateFormat.dayTime), '19-02-2018 14:05');
      expect(formatDate(moment, DateFormat.iso), '2018-02-19');
      expect(formatDate(moment, DateFormat.isoTime), '2018-02-19 14:05');
    });

    test('даты нет — пусто в любом виде', () {
      for (final format in DateFormat.values) {
        expect(formatDate(null, format), '', reason: format.id);
      }
    });

    test('незнакомое имя формата — это умолчание', () {
      expect(DateFormat.byId('такого-нет'), DateFormat.day);
    });
  });

  group('права', () {
    const file = FileAttributes(mode: 0x1ED, modeString: 'drwxr-xr-x');

    test('буквами, числом и обоими разом', () {
      expect(formatMode(file), 'drwxr-xr-x');
      expect(formatMode(file, ModeFormat.octal), '755');
      expect(formatMode(file, ModeFormat.both), 'drwxr-xr-x 755');
    });

    test('четыре разряда — там, где важны setuid и sticky', () {
      expect(formatMode(file, ModeFormat.octal, 4), '0755');
    });

    test('атрибутов нет — пусто, а не нули', () {
      expect(formatMode(const FileAttributes.unknown()), '');
      expect(formatMode(const FileAttributes.unknown(), ModeFormat.octal), '');
    });
  });
}
