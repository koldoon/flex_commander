import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Значение атрибутов: то, что оно решает само.
void main() {
  group('значение расширенного атрибута', () {
    test('печатный текст показывается текстом', () {
      expect(Xattr('com.apple.quarantine', utf8.encode('0083;68b8;Safari;')).text, '0083;68b8;Safari;');
      expect(Xattr('note', utf8.encode('метка по-русски')).text, 'метка по-русски');
    });

    test('пустое значение — пустая строка, а не двоичное', () {
      // Атрибут-флаг: он есть, а байтов у него нет.
      expect(const Xattr('flag', []).text, '');
    });

    test('двоичное текстом не притворяется', () {
      // `com.apple.FinderInfo` — тридцать два байта, среди которых нули.
      expect(Xattr('com.apple.FinderInfo', List.filled(32, 0)).text, isNull);
      expect(const Xattr('bytes', [0xC3, 0x28]).text, isNull, reason: 'не разбирается как UTF-8');
      expect(const Xattr('bytes', [7, 8, 9]).text, isNull, reason: 'управляющие символы — не текст');
    });

    test('перевод строки текстом быть не мешает', () {
      // Таб — единственный управляющий символ, который в значении осмыслен.
      expect(Xattr('list', utf8.encode('раз\tдва')).text, 'раз\tдва');
    });
  });

  group('сборка значения', () {
    const base = NodeAttributes(mode: 0x81A4, modeString: '-rw-r--r--', uid: 501, gid: 20, canEditMode: true);

    test('имена дописываются, не трогая остального', () {
      final named = base.withNames(owner: 'koldoon', group: 'staff');

      expect(named.owner, 'koldoon');
      expect(named.group, 'staff');
      expect(named.uid, 501);
      expect(named.canEditMode, isTrue);
      expect(named.canEditXattrs, isFalse);
    });

    test('расширенные атрибуты приносят с собой право их править', () {
      final marked = base.withXattrs([
        const Xattr('a', [1]),
      ]);

      // Право приходит вместе со списком: спросить об этом отдельно не у кого,
      // а флаг «наверное, есть» был бы обещанием без обеспечения.
      expect(marked.canEditXattrs, isTrue);
      expect(marked.xattrs, hasLength(1));
      expect(marked.modeString, '-rw-r--r--');
    });

    test('права отделяются от типа объекта', () {
      // В `mode` лежит и тип: `0x81A4` — это обычный файл с правами `644`.
      expect(base.permissions, 0x1A4);
    });

    test('пустое значение ничего не обещает', () {
      expect(NodeAttributes.unknown.canEditMode, isFalse);
      expect(NodeAttributes.unknown.canEditTimes, isFalse);
      expect(NodeAttributes.unknown.canEditOwner, isFalse);
      expect(NodeAttributes.unknown.canEditXattrs, isFalse);
      expect(NodeAttributes.unknown.mode, 0);
    });
  });
}
