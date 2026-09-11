import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор списков каталога.
///
/// Образцы настоящие — сняты с `cios.dhitechnical.com`, каталог `/Cisco/16xx`
/// (`docs/spec/ftp.md`, §3).
void main() {
  group('MLSD', () {
    const file =
        'modify=20200926030759;perm=adfr;size=10402700;type=file;unique=48UC01;'
        'UNIX.group=33;UNIX.groupname=autotier;UNIX.mode=0644;UNIX.owner=33;'
        'UNIX.ownername=anonftp; c1600-nosy-l.122-5a.bin';

    test('файл разбирается целиком', () {
      final entry = FtpListing.parseMachine(file)!;

      expect(entry.name, 'c1600-nosy-l.122-5a.bin');
      expect(entry.type, FileType.regular);
      expect(entry.size, 10402700);
      expect(entry.mode, 0x1A4, reason: '0644 восьмеричное');
      expect(entry.owner, 'anonftp');
      expect(entry.group, 'autotier');
      expect(entry.modified, DateTime.utc(2020, 9, 26, 3, 7, 59).toLocal());
      expect(entry.permissions, 'adfr');
    });

    test('каталог с особым битом', () {
      final entry =
          FtpListing.parseMachine(
            'modify=20260820064604;perm=fle;type=dir;unique=48U480;UNIX.group=33;'
            'UNIX.groupname=autotier;UNIX.mode=02755;UNIX.owner=33;UNIX.ownername=anonftp; C980',
          )!;

      expect(entry.name, 'C980');
      expect(entry.isDirectory, isTrue);
      expect(entry.mode, 1517, reason: '02755 восьмеричное, вместе с setgid');
    });

    test('свой и родительский каталоги выбрасываются', () {
      expect(FtpListing.parseMachine('modify=20250901194129;perm=fle;type=cdir;unique=48U102; .'), isNull);
      expect(FtpListing.parseMachine('modify=20260822010150;perm=fle;type=pdir;unique=48U2; ..'), isNull);
    });

    test('имя с пробелами доходит целиком', () {
      final entry =
          FtpListing.parseMachine(
            'modify=20250901163122;perm=adfr;size=6886273;type=file;unique=48U2005CC;'
            'UNIX.mode=0644; c1600-k8Osy-Mz 123-9 By Hd.bin',
          )!;

      expect(entry.name, 'c1600-k8Osy-Mz 123-9 By Hd.bin');
    });

    test('точка с запятой в имени не обрывает разбор', () {
      final entry = FtpListing.parseMachine('size=10;type=file; странное;имя.txt')!;

      expect(entry.name, 'странное;имя.txt');
      expect(entry.size, 10);
    });

    test('чего сервер не сказал, того и нет', () {
      final entry = FtpListing.parseMachine('type=file; plain.txt')!;

      expect(entry.size, FsNode.unknownSize);
      expect(entry.mode, 0);
      expect(entry.owner, isEmpty);
      expect(entry.modified, isNull);
      expect(entry.writable, isNull, reason: 'не сказал — врать нельзя');
    });

    test('строка не по формату даёт null', () {
      expect(FtpListing.parseMachine('совсем не то'), isNull);
      expect(FtpListing.parseMachine('type=file; '), isNull);
    });

    test('право писать берётся у сервера', () {
      expect(FtpListing.parseMachine('perm=adfr;type=file; a.bin')!.writable, isTrue);
      expect(FtpListing.parseMachine('perm=fle;type=dir; ro')!.writable, isFalse);
      expect(FtpListing.parseMachine('perm=flecm;type=dir; rw')!.writable, isTrue);
    });
  });

  group('LIST по-юниксовому', () {
    test('файл', () {
      final entry =
          FtpListing.parseText('-rw-r--r--   1 33       33        6911803 Sep 26  2020 C1600-K8osy-Mz.123-5a.bin')!;

      expect(entry.name, 'C1600-K8osy-Mz.123-5a.bin');
      expect(entry.type, FileType.regular);
      expect(entry.size, 6911803);
      expect(entry.owner, '33');
      expect(entry.group, '33');
      expect(entry.mode, 0x1A4);
      expect(entry.modified, DateTime(2020, 9, 26));
    });

    test('имя из нескольких слов доходит целиком', () {
      // Разбор через split теряет всё после первого пробела, а таких имён на
      // живом сервере полкаталога (`docs/spec/ftp.md`, §3.5).
      final entry =
          FtpListing.parseText('-rw-r--r--   1 33       33        3491840 Sep  1  2025 c1600-K8osy-Mz 122-15 T5.bin')!;

      expect(entry.name, 'c1600-K8osy-Mz 122-15 T5.bin');
      expect(entry.size, 3491840);
    });

    test('каталог: размер у него ничего не значит', () {
      final entry = FtpListing.parseText('drwxr-sr-x   7 33       33              7 May  1 05:01 10k')!;

      expect(entry.name, '10k');
      expect(entry.isDirectory, isTrue);
      expect(entry.size, FsNode.unknownSize);
      expect(entry.mode, 1517, reason: 'setgid виден по s в группе');
    });

    test('ссылка отдаёт и имя, и цель', () {
      final entry =
          FtpListing.parseText('lrwxrwxrwx   1 0        0               9 Jan  3  2024 latest -> current/x.bin')!;

      expect(entry.name, 'latest');
      expect(entry.isLink, isTrue);
      expect(entry.linkTarget, 'current/x.bin');
    });

    test('время вместо года значит этот год', () {
      final now = DateTime(2026, 6, 1, 12);
      final entry = FtpListing.parseText('-rw-r--r-- 1 u g 10 May  1 05:01 fresh.txt', now: now)!;

      expect(entry.modified, DateTime(2026, 5, 1, 5, 1));
    });

    test('дата в будущем значит прошлый год', () {
      // Так считает `ls`: иначе файл, тронутый в декабре, в январе уезжает на
      // год вперёд.
      final now = DateTime(2026, 1, 10, 12);
      final entry = FtpListing.parseText('-rw-r--r-- 1 u g 10 Dec 20 23:30 old.txt', now: now)!;

      expect(entry.modified, DateTime(2025, 12, 20, 23, 30));
    });
  });

  group('LIST по-досовски', () {
    test('каталог', () {
      final entry = FtpListing.parseText('03-07-24  10:22AM       <DIR>          pub')!;

      expect(entry.name, 'pub');
      expect(entry.isDirectory, isTrue);
      expect(entry.modified, DateTime(2024, 3, 7, 10, 22));
    });

    test('файл после полудня', () {
      final entry = FtpListing.parseText('12-31-25  09:05PM             1048576 readme и пробел.txt')!;

      expect(entry.name, 'readme и пробел.txt');
      expect(entry.size, 1048576);
      expect(entry.modified, DateTime(2025, 12, 31, 21, 5));
    });

    test('полночь — это ноль часов', () {
      expect(FtpListing.parseText('01-02-26  12:30AM  5 a.txt')!.modified, DateTime(2026, 1, 2, 0, 30));
    });
  });

  group('мусор', () {
    test('пустая строка и чужой формат дают null', () {
      expect(FtpListing.parseText(''), isNull);
      expect(FtpListing.parseText('   '), isNull);
      expect(FtpListing.parseText('total 42'), isNull);
      expect(FtpListing.parseText('-rw-r--r-- мало полей'), isNull);
    });
  });

  group('время по RFC 3659', () {
    test('MDTM разбирается как UTC', () {
      expect(FtpListing.parseStamp('20200926030759'), DateTime.utc(2020, 9, 26, 3, 7, 59).toLocal());
    });

    test('дробная часть не мешает', () {
      expect(FtpListing.parseStamp('20200926030759.123'), DateTime.utc(2020, 9, 26, 3, 7, 59).toLocal());
    });

    test('короткое и битое дают null', () {
      expect(FtpListing.parseStamp('2020'), isNull);
      expect(FtpListing.parseStamp('нетакойдаты!!'), isNull);
      expect(FtpListing.parseStamp(null), isNull);
    });
  });
}
