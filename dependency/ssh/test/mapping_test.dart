import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_sftp.dart';

void main() {
  late SftpTreeProvider provider;
  late DirectoryNode parent;

  setUp(() {
    provider = SftpTreeProvider(
      target: SshTarget.parse(Uri.parse('ssh://tester@host/')),
      sftp: FakeSftp(),
      homePath: '/home/tester',
    );
    parent = provider.rootDirectory;
  });

  group('путь для оболочки сервера', () {
    test('адрес панели уходит, остаётся путь', () {
      // Оболочка стоит **на сервере** и про наши адреса не слышала: пришли ей
      // `ssh://tester@host/srv` — и получишь `No such file or directory`.
      expect(provider.shellPath('ssh://tester@host/srv/www'), '/srv/www');
      expect(provider.shellPath('ssh://tester@host/'), '/');
    });

    test('схему тоже режем', () {
      // Путь панели несёт её, а `authority` — нет: срезанное с начала не
      // совпало бы никогда, и в `cd` уезжал бы адрес целиком.
      expect(provider.shellPath('ssh://tester@host'), '/');
    });

    test('путь без адреса остаётся собой', () {
      // По дереву ходят уже без адреса — трогать такой путь нечего.
      expect(provider.shellPath('/etc'), '/etc');
    });
  });

  group('права из режима доступа', () {
    test('обычный файл', () => expect(permissionsOf(0x1A4), 'rw-r--r--')); // 0644
    test('каталог', () => expect(permissionsOf(0x1ED), 'rwxr-xr-x')); // 0755
    test('только владельцу', () => expect(permissionsOf(0x180), 'rw-------')); // 0600
    test('всем всё', () => expect(permissionsOf(0x1FF), 'rwxrwxrwx')); // 0777
    test('ничего', () => expect(permissionsOf(0), '---------'));

    test('старшие биты режима на права не влияют', () {
      // 0100644: тип файла в тех же битах, что и права, но выше.
      expect(permissionsOf(0x81A4), 'rw-r--r--');
    });
  });

  group('запись сервера — узлом', () {
    test('файл: размер, дата и строка атрибутов', () {
      final modified = DateTime(2026, 3, 14, 15, 9);
      final node = nodeFromEntry(
        SftpEntry(name: 'notes.txt', type: FileType.regular, size: 42, mode: 0x81A4, modified: modified),
        parent,
        provider,
      );

      expect(node, isA<FileNode>());
      expect(node.name, 'notes.txt');
      expect(node.size, 42);
      expect((node as FileNode).modified, modified);
      expect(node.attributes.modeString, '-rw-r--r--');
      expect(node.executable, isFalse);
    });

    test('каталог', () {
      final node = nodeFromEntry(
        const SftpEntry(name: 'srv', type: FileType.directory, mode: 0x41ED),
        parent,
        provider,
      );

      expect(node, isA<DirectoryNode>());
      expect((node as DirectoryNode).attributes.modeString, 'drwxr-xr-x');
      expect(node.size, FsNode.unknownSize);
    });

    test('исполняемый файл виден по правам', () {
      final node = nodeFromEntry(
        const SftpEntry(name: 'run.sh', type: FileType.regular, size: 10, mode: 0x81ED),
        parent,
        provider,
      );

      expect((node as FileNode).executable, isTrue);
      expect(node.attributes.modeString, '-rwxr-xr-x');
    });

    test('ссылка помнит, куда ведёт, и что там лежит', () {
      final node = nodeFromEntry(
        const SftpEntry(name: 'www', type: FileType.symbolicLink, mode: 0xA1FF, linkTarget: '/srv/www'),
        parent,
        provider,
        linkTargetType: FileType.directory,
      );

      expect(node, isA<LinkNode>());
      expect((node as LinkNode).reference, '/srv/www');
      expect(node.isDirectoryLink, isTrue);
      expect(node.broken, isFalse);
      expect(node.attributes.modeString, 'lrwxrwxrwx');
    });

    test('ссылка без цели — битая', () {
      final node = nodeFromEntry(
        const SftpEntry(name: 'gone', type: FileType.symbolicLink, mode: 0xA1FF, linkTarget: '/nowhere'),
        parent,
        provider,
      );

      expect((node as LinkNode).broken, isTrue);
    });

    test('без атрибутов строка пустая, а не выдуманная', () {
      final node = nodeFromEntry(const SftpEntry(name: 'x', type: FileType.regular, size: 1), parent, provider);

      expect((node as FileNode).attributes.modeString, isEmpty);
    });
  });
}
