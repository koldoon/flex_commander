import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор ответов сервера.
///
/// Образцы настоящие — сняты с `cios.dhitechnical.com`
/// (`docs/spec/ftp.md`, §3).
void main() {
  FtpReply? feed(List<String> lines) {
    final reader = FtpReplyReader();
    FtpReply? last;
    for (final line in lines) {
      last = reader.add(line) ?? last;
    }
    return last;
  }

  group('однострочный ответ', () {
    test('код и текст разбираются', () {
      final reply = feed(['230 Anonymous access granted, restrictions apply'])!;

      expect(reply.code, 230);
      expect(reply.message, 'Anonymous access granted, restrictions apply');
      expect(reply.isComplete, isTrue);
      expect(reply.isPositive, isTrue);
    });

    test('отказ виден по первой цифре', () {
      final reply = feed(['550 /нет-такого: No such file or directory'])!;

      expect(reply.kind, 5);
      expect(reply.isPositive, isFalse);
      expect(reply.isComplete, isFalse);
    });

    test('готовность принять данные — это 150 или 125', () {
      expect(feed(['150 Opening ASCII mode data connection for MLSD'])!.isAboutToTransfer, isTrue);
      expect(feed(['125 Data connection already open'])!.isAboutToTransfer, isTrue);
      expect(feed(['226 Transfer complete'])!.isAboutToTransfer, isFalse);
    });
  });

  group('многострочный ответ', () {
    test('кончается строкой с тем же кодом, а не первым попавшимся пробелом', () {
      // Настоящее приветствие: баннер из ASCII-арта, и в нём есть строки, у
      // которых на четвёртом месте пробел. Наивная проверка обрывает ответ
      // здесь и дальше врёт до конца сеанса (`docs/spec/ftp.md`, §3.1).
      final reader = FtpReplyReader();

      expect(reader.add(r'220-$$$$$$$\  $$\   $$\ $$$$$$\       $$$$$$$$\'), isNull);
      expect(
        reader.add(r'   $$  __$$\ $$ |  $$ |\_$$  _|      \__$$  __|'),
        isNull,
        reason: 'пробел на четвёртом месте',
      );
      expect(reader.add(r'   $$ |  $$ |$$$$$$$$ |  $$ |           $$ |   '), isNull);
      expect(reader.add('   '), isNull);
      expect(reader.isWaiting, isTrue);

      final reply = reader.add('220 Proceed.')!;
      expect(reply.code, 220);
      expect(reply.lines.length, 5);
    });

    test('строка с чужим кодом концом не считается', () {
      final reader = FtpReplyReader();
      reader.add('211-Features:');
      expect(reader.add('250 End of list'), isNull, reason: 'код чужой');

      final reply = reader.add('211 End')!;
      expect(reply.code, 211);
    });

    test('середина отбита пробелом — это MLST', () {
      final reply =
          feed([
            '250-Start of list for /Cisco/16xx/c1600-nosy-l.122-5a.bin',
            ' modify=20200926030759;perm=adfr;size=10402700;type=file;',
            '250 End of list',
          ])!;

      expect(reply.code, 250);
      expect(reply.message, 'modify=20200926030759;perm=adfr;size=10402700;type=file;');
    });

    test('возможности сервера читаются из середины', () {
      final reply = feed(['211-Features:', ' AUTH TLS', ' MLST modify*;size*;', ' REST STREAM', '211 End'])!;

      expect(reply.code, 211);
      expect(reply.message.split('\n').map((line) => line.trim()), ['AUTH TLS', 'MLST modify*;size*;', 'REST STREAM']);
    });
  });

  group('строка, которая кодом не является', () {
    test('отдаётся как есть, а не теряется', () {
      final reply = feed(['Connection reset by peer'])!;

      expect(reply.code, 0);
      expect(reply.isPositive, isFalse);
      expect(reply.message, 'Connection reset by peer');
    });

    test('код с чужим разделителем кодом не считается', () {
      expect(feed(['220:Proceed'])!.code, 0);
    });
  });
}
