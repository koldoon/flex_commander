import 'package:fc_7z/src/seven_zip_listing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вывод настоящей программы: шапка с версией, свойства архива, а уже потом
/// записи. Всё, что здесь проверяется, разбирается из этого текста — своего
/// формата у модуля нет.
const String _listing = '''
7-Zip 24.09 (arm64) : Copyright (c) 1999-2024 Igor Pavlov : 2024-11-29
 64-bit locale=en_US.UTF-8 Threads:8, ASM

Scanning the drive for archives:
1 file, 4096 bytes (4 KiB)

Listing archive: /tmp/sample.7z

--
Path = /tmp/sample.7z
Type = 7z
Physical Size = 4096
Headers Size = 218
Method = LZMA2:12
Solid = +
Blocks = 1

----------
Path = docs
Size = 0
Packed Size = 0
Modified = 2026-08-19 10:00:00
Attributes = D_ drwxr-xr-x
CRC =
Encrypted = -
Method =
Block =

Path = docs/readme.txt
Size = 120
Packed Size = 64
Modified = 2026-08-19 10:01:02
Attributes = A_ -rw-r--r--
CRC = 1A2B3C4D
Encrypted = -
Method = LZMA2:12
Block = 0

Path = docs/inner/deep.bin
Size = 900
Packed Size = 400
Modified = 2026-08-19 10:02:03
Attributes = A_ -rwxr-xr-x
CRC = FFEEDDCC
Encrypted = -
Method = LZMA2:12
Block = 0
''';

void main() {
  group('оглавление', () {
    final listing = parseSevenZipListing(_listing);

    test('шапка и свойства архива в записи не попадают', () {
      expect(listing.root.children.keys, ['docs']);
    });

    test('запись читается целиком', () {
      final entry = listing.at(['docs', 'readme.txt'])!;

      expect(entry.isDirectory, isFalse);
      expect(entry.entryName, 'docs/readme.txt');
      expect(entry.size, 120);
      expect(entry.modified, DateTime(2026, 8, 19, 10, 1, 2));
      expect(entry.encrypted, isFalse);
    });

    test('каталог узнаётся по признаку D', () {
      expect(listing.at(['docs'])!.isDirectory, isTrue);
      expect(listing.at(['docs'])!.modified, DateTime(2026, 8, 19, 10));
    });

    test('промежуточный каталог достраивается по пути', () {
      // `docs/inner` в архиве отдельной записью не лежит.
      final inner = listing.at(['docs', 'inner'])!;

      expect(inner.isDirectory, isTrue);
      expect(inner.modified, isNull, reason: 'о достроенном каталоге ничего не известно');
      expect(inner.children.keys, ['deep.bin']);
    });

    test('права разбираются из хвоста признаков', () {
      expect(listing.at(['docs', 'readme.txt'])!.mode, 0x1A4, reason: 'rw-r--r--');
      expect(listing.at(['docs', 'inner', 'deep.bin'])!.mode, 0x1ED, reason: 'rwxr-xr-x');
      expect(listing.at(['docs'])!.mode, 0x1ED);
    });
  });

  group('что бывает в выводе', () {
    test('каталог, объявленный после своего содержимого, детей не теряет', () {
      final listing = parseSevenZipListing('''
----------
Path = docs/readme.txt
Size = 10
Attributes = A_ -rw-r--r--

Path = docs
Size = 0
Modified = 2026-08-19 10:00:00
Attributes = D_ drwxr-xr-x
''');

      final docs = listing.at(['docs'])!;
      expect(docs.isDirectory, isTrue);
      expect(docs.modified, isNotNull, reason: 'запись каталога принесла дату');
      expect(docs.children.keys, ['readme.txt']);
    });

    test('пустой каталог остаётся каталогом', () {
      final listing = parseSevenZipListing('''
----------
Path = empty
Size = 0
Attributes = D_ drwxr-xr-x
''');

      expect(listing.at(['empty'])!.isDirectory, isTrue);
      expect(listing.at(['empty'])!.children, isEmpty);
    });

    test('признак Folder тоже объявляет каталог', () {
      final listing = parseSevenZipListing('''
----------
Path = stuff
Folder = +
Size = 0
Attributes =
''');

      expect(listing.at(['stuff'])!.isDirectory, isTrue);
    });

    test('имена с пробелами и кириллицей', () {
      final listing = parseSevenZipListing('''
----------
Path = мои файлы/отчёт за год.txt
Size = 42
Attributes = A_ -rw-r--r--
''');

      expect(listing.at(['мои файлы', 'отчёт за год.txt'])!.size, 42);
    });

    test('обратная косая черта из архива, собранного на Windows', () {
      final listing = parseSevenZipListing('''
----------
Path = docs\\win\\file.txt
Size = 7
Attributes = A_
''');

      expect(listing.at(['docs', 'win', 'file.txt'])!.size, 7);
    });

    test('windows-архив без прав: режим неизвестен', () {
      final listing = parseSevenZipListing('''
----------
Path = file.txt
Size = 7
Attributes = A
''');

      expect(listing.at(['file.txt'])!.mode, 0);
    });

    test('шифрованная запись отмечена', () {
      final listing = parseSevenZipListing('''
----------
Path = secret.txt
Size = 16
Attributes = A_ -rw-r--r--
Encrypted = +
''');

      expect(listing.at(['secret.txt'])!.encrypted, isTrue);
    });

    test('пустые размер и дата не рушат разбор', () {
      final listing = parseSevenZipListing('''
----------
Path = odd.txt
Size =
Modified =
Attributes = A_ -rw-r--r--
''');

      final entry = listing.at(['odd.txt'])!;
      expect(entry.size, 0);
      expect(entry.modified, isNull);
    });

    test('доли секунды в дате', () {
      final listing = parseSevenZipListing('''
----------
Path = odd.txt
Size = 1
Modified = 2026-08-19 10:01:02.1234567
Attributes = A_ -rw-r--r--
''');

      expect(listing.at(['odd.txt'])!.modified, DateTime(2026, 8, 19, 10, 1, 2));
    });

    test('возврат каретки в переводе строки', () {
      final listing = parseSevenZipListing(
        '----------\r\nPath = file.txt\r\nSize = 5\r\nAttributes = A_ -rw-r--r--\r\n',
      );

      expect(listing.at(['file.txt'])!.size, 5);
    });

    test('вывод без разделителя разбирается целиком', () {
      // Так выглядит вывод, если шапку когда-нибудь отключат: терять из-за
      // этого весь архив нельзя.
      final listing = parseSevenZipListing('''
Path = file.txt
Size = 5
Attributes = A_ -rw-r--r--
''');

      expect(listing.at(['file.txt'])!.size, 5);
    });

    test('пустой архив — пустое дерево, а не ошибка', () {
      expect(parseSevenZipListing('----------\n').root.children, isEmpty);
    });

    test('одноимённые записи: побеждает последняя', () {
      final listing = parseSevenZipListing('''
----------
Path = file.txt
Size = 1
Attributes = A_ -rw-r--r--

Path = file.txt
Size = 2
Attributes = A_ -rw-r--r--
''');

      expect(listing.at(['file.txt'])!.size, 2);
    });
  });
}
