import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Атрибуты файла средствами системы: `chmod(2)`, `utimensat(2)`, `chown(2)` и
/// расширенные атрибуты через FFI.
///
/// Проверяется на настоящем диске, и иначе нельзя: ошибка в подписи FFI не
/// бросает исключение, а роняет процесс, — а неверная константа («не трогать
/// эту дату») молча ставит 1970 год вместо того, чтобы отказать.
void main() {
  late Directory temp;
  late String root;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('flex_commander_attrs');
    root = await temp.resolveSymbolicLinks();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<String> makeFile(String name) async {
    final path = p.join(root, name);
    await File(path).writeAsString('body', flush: true);
    return path;
  }

  group('режим', () {
    test('назначается и виден в stat', () async {
      final path = await makeFile('mode.txt');
      LocalMode.instance!.apply(path, 0x180); // 0600
      expect(File(path).statSync().mode & 0xFFF, 0x180);

      LocalMode.instance!.apply(path, 0x1ED); // 0755
      expect(File(path).statSync().mode & 0xFFF, 0x1ED);
    });

    test('несуществующий путь — отказ, а не молчание', () {
      expect(
        () => LocalMode.instance!.apply(p.join(root, 'нет'), 0x1A4),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.notFound)),
      );
    });
  });

  group('даты', () {
    test('назначаются обе', () async {
      final path = await makeFile('both.txt');
      final modified = DateTime.utc(2021, 3, 4, 5, 6, 7);
      final accessed = DateTime.utc(2022, 8, 9, 10, 11, 12);

      LocalTimes.instance!.apply(path, modified: modified, accessed: accessed);

      final stat = File(path).statSync();
      expect(stat.modified.toUtc(), modified);
      expect(stat.accessed.toUtc(), accessed);
    });

    test('пропущенная дата остаётся прежней', () async {
      final path = await makeFile('one.txt');
      final was = DateTime.utc(2019, 1, 2, 3, 4, 5);
      LocalTimes.instance!.apply(path, modified: was, accessed: was);

      LocalTimes.instance!.apply(path, modified: DateTime.utc(2020, 6, 7, 8, 9, 10));

      // Ради этого и взят `utimensat` вместо `utimes`: тот требует обе даты
      // сразу, и вторую пришлось бы читать и записывать обратно.
      expect(File(path).statSync().accessed.toUtc(), was);
    });

    test('дата до 1970 года не уезжает на секунду', () async {
      final path = await makeFile('old.txt');
      final ancient = DateTime.utc(1965, 5, 5, 5, 5, 5);

      LocalTimes.instance!.apply(path, modified: ancient);

      expect(File(path).statSync().modified.toUtc(), ancient);
    });

    test('каталогу дата тоже назначается', () async {
      final path = p.join(root, 'каталог');
      await Directory(path).create();
      final modified = DateTime.utc(2018, 11, 12, 13, 14, 15);

      // Именно поэтому здесь FFI, а не `File.setLastModified`: у каталога
      // такого метода нет вовсе.
      LocalTimes.instance!.apply(path, modified: modified);

      expect(Directory(path).statSync().modified.toUtc(), modified);
    });

    test('ничего не назначив, ничего не портит', () async {
      final path = await makeFile('none.txt');
      final was = File(path).statSync().modified;

      LocalTimes.instance!.apply(path);

      expect(File(path).statSync().modified, was);
    });
  });

  group('владелец', () {
    test('свой же остаётся своим', () async {
      final path = await makeFile('own.txt');
      // Назначение того, что и так стоит, обязано проходить: иначе окно
      // ругалось бы на «Apply», в котором владельца не трогали.
      expect(() => LocalOwner.instance!.apply(path, gid: _gidOf(path)), returnsNormally);
      expect(_gidOf(path), isNonNegative);
    });

    test('ничего не назначив, ничего не делает', () async {
      final path = await makeFile('keep.txt');
      expect(() => LocalOwner.instance!.apply(path), returnsNormally);
    });

    test('чужой — отказ, показанный как есть', () async {
      if (_amRoot()) {
        markTestSkipped('запущено от суперпользователя: отказывать некому');
        return;
      }
      final path = await makeFile('root.txt');
      expect(
        () => LocalOwner.instance!.apply(path, uid: 0),
        throwsA(isA<FsError>().having((error) => error.kind, 'kind', FsErrorKind.permissionDenied)),
      );
    });
  });

  group('расширенные атрибуты', () {
    test('у нового файла их нет', () async {
      final path = await makeFile('clean.txt');
      expect(LocalXattr.instance!.names(path), isEmpty);
    });

    test('кладутся, находятся, читаются и убираются', () async {
      final xattr = LocalXattr.instance!;
      final path = await makeFile('marked.txt');

      xattr.write(path, 'com.example.note', utf8.encode('привет'));

      expect(xattr.names(path), ['com.example.note']);
      expect(xattr.read(path, 'com.example.note'), utf8.encode('привет'));

      xattr.erase(path, 'com.example.note');
      expect(xattr.names(path), isEmpty);
    });

    test('двоичное значение возвращается байт в байт', () async {
      final xattr = LocalXattr.instance!;
      final path = await makeFile('binary.txt');
      final value = Uint8List.fromList([0, 1, 0, 255, 0, 128, 0]);

      xattr.write(path, 'com.example.bytes', value);

      // Нули внутри значения — не конец строки: именно на этом ломается
      // всякая попытка возить расширенные атрибуты текстом.
      expect(xattr.read(path, 'com.example.bytes'), value);
    });

    test('пустое значение — это тоже значение', () async {
      final xattr = LocalXattr.instance!;
      final path = await makeFile('empty.txt');

      xattr.write(path, 'com.example.flag', const []);

      expect(xattr.names(path), ['com.example.flag']);
      expect(xattr.read(path, 'com.example.flag'), isEmpty);
    });

    test('несколько атрибутов приходят по именам, а не одной кашей', () async {
      final xattr = LocalXattr.instance!;
      final path = await makeFile('many.txt');

      xattr.write(path, 'com.example.a', const [1]);
      xattr.write(path, 'com.example.b', const [2]);

      expect(xattr.names(path)..sort(), ['com.example.a', 'com.example.b']);
    });

    test('отсутствующий атрибут — null, а не ошибка', () async {
      final path = await makeFile('nothing.txt');
      expect(LocalXattr.instance!.read(path, 'com.example.absent'), isNull);
    });

    test('убрать то, чего нет, — не ошибка', () async {
      final path = await makeFile('gone.txt');
      expect(() => LocalXattr.instance!.erase(path, 'com.example.absent'), returnsNormally);
    });

    test('карантин снимается', () async {
      final xattr = LocalXattr.instance!;
      final path = await makeFile('quarantined.txt');
      // Ровно тот случай, ради которого расширенные атрибуты и вошли в этап.
      xattr.write(path, 'com.apple.quarantine', utf8.encode('0083;68b8;Safari;'));
      expect(xattr.names(path), contains('com.apple.quarantine'));

      xattr.erase(path, 'com.apple.quarantine');

      expect(xattr.names(path), isEmpty);
    });
  });

  group('числа владельца', () {
    test('сходятся с тем, что говорит система', () async {
      final path = await makeFile('numbers.txt');
      final own = LocalStat.instance!.ownerOf(path);

      // Единственная возможная сверка: раскладка `struct stat` не отказывает
      // при ошибке, а тихо отдаёт чужие байты как числа владельца.
      expect(own, isNotNull);
      expect(own!.uid, _statField(path, '%u'));
      expect(own.gid, _statField(path, '%g'));
    });

    test('несуществующего пути нет и владельца', () {
      expect(LocalStat.instance!.ownerOf(p.join(root, 'нет')), isNull);
    });
  });

  group('имена пользователей', () {
    test('своё имя — то же, что у `id -un`', () {
      final uid = int.parse(Process.runSync('id', ['-u']).stdout.toString().trim());
      final name = Process.runSync('id', ['-un']).stdout.toString().trim();

      // Ровно тот случай, из-за которого разбор `/etc/passwd` не годится: на
      // macOS обычного пользователя в этом файле нет вовсе.
      expect(LocalUsers.instance!.userName(uid), name);
    });

    test('своя группа — то же, что у `id -gn`', () {
      final gid = int.parse(Process.runSync('id', ['-g']).stdout.toString().trim());
      final name = Process.runSync('id', ['-gn']).stdout.toString().trim();

      expect(LocalUsers.instance!.groupName(gid), name);
    });

    test('имя разбирается обратно в число', () {
      final uid = int.parse(Process.runSync('id', ['-u']).stdout.toString().trim());
      final name = Process.runSync('id', ['-un']).stdout.toString().trim();

      expect(LocalUsers.instance!.userId(name), uid);
      expect(LocalUsers.instance!.groupId('staff'), 20);
    });

    test('неизвестное имя — null, неизвестное число — пусто', () {
      expect(LocalUsers.instance!.userId('такого-точно-нет'), isNull);
      expect(LocalUsers.instance!.groupId('такой-точно-нет'), isNull);
      expect(LocalUsers.instance!.userName(65123), isEmpty);
    });

    test('root зовут root', () {
      expect(LocalUsers.instance!.userName(0), 'root');
    });
  });
}

bool _amRoot() => Process.runSync('id', ['-u']).stdout.toString().trim() == '0';

int _gidOf(String path) => int.parse(Process.runSync('stat', ['-f', '%g', path]).stdout.toString().trim());
int _statField(String path, String format) =>
    int.parse(Process.runSync('stat', ['-f', format, path]).stdout.toString().trim());
