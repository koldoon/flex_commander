import 'dart:io';

import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ssh/fc_ssh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('разбор адреса', () {
    test('пользователь, хост, порт и путь', () {
      final target = SshTarget.parse(Uri.parse('ssh://koldoon@example.org:2222/srv/www'));

      expect(target.user, 'koldoon');
      expect(target.host, 'example.org');
      expect(target.port, 2222);
      expect(target.path, '/srv/www');
    });

    test('без пользователя — текущий', () {
      final target = SshTarget.parse(Uri.parse('ssh://example.org/'));

      expect(target.user, Platform.environment['USER'] ?? Platform.environment['LOGNAME'] ?? '');
    });

    test('порт по умолчанию в пути не пишется', () {
      expect(SshTarget.parse(Uri.parse('ssh://a@host/x')).authority, '//a@host');
      expect(SshTarget.parse(Uri.parse('ssh://a@host:22/x')).authority, '//a@host');
      expect(SshTarget.parse(Uri.parse('ssh://a@host:2222/x')).authority, '//a@host:2222');
    });

    test('пароль из адреса берётся, но в путь не попадает', () {
      final target = SshTarget.parse(Uri.parse('ssh://a:s3cret@host/x'));

      expect(target.passwordFromAddress, 's3cret');
      expect(target.authority, '//a@host');
      expect(target.authority, isNot(contains('s3cret')));
      expect(target.realm, isNot(contains('s3cret')));
      expect(target.display, isNot(contains('s3cret')));
      expect(target.toString(), isNot(contains('s3cret')));
    });

    test('область запоминания — сервер целиком, вместе с портом', () {
      expect(SshTarget.parse(Uri.parse('ssh://a@host/x')).realm, 'ssh:a@host:22');
      expect(SshTarget.parse(Uri.parse('ssh://a@host:2222/x')).realm, 'ssh:a@host:2222');
    });
  });

  group('начало пути', () {
    final target = SshTarget.parse(Uri.parse('ssh://a@host/'));

    test('снимается, если оно есть', () {
      expect(target.stripAuthority('//a@host/srv/www'), '/srv/www');
      expect(target.stripAuthority('//a@host'), '/');
      expect(target.stripAuthority('//a@host/'), '/');
    });

    test('обычный путь остаётся собой', () {
      expect(target.stripAuthority('/srv/www'), '/srv/www');
      expect(target.stripAuthority('/'), '/');
    });
  });

  group('путь узла разбирается обратно в тот же адрес', () {
    test('без порта', () {
      final path = NodePath.parse('ssh://a@host/srv/www');

      expect(path.parts, hasLength(1));
      expect(path.scheme, 'ssh');
      expect(path.parts.first.path, '//a@host/srv/www');
      expect(path.toString(), 'ssh://a@host/srv/www');
    });

    test('с портом: двоеточие хоста схемой не считается', () {
      final path = NodePath.parse('ssh://a@host:2222/srv');

      expect(path.parts, hasLength(1));
      expect(path.parts.first.path, '//a@host:2222/srv');
      expect(path.toString(), 'ssh://a@host:2222/srv');
    });

    test('показывается со схемой: без неё «//a@host» — ни адрес, ни путь', () {
      expect(NodePath.parse('ssh://a@host/srv').displayString, 'ssh://a@host/srv');
      expect(NodePath.parse('ssh://a@host:2222/srv').displayString, 'ssh://a@host:2222/srv');
    });

    test('а локальный путь по-прежнему выглядит обычным путём', () {
      expect(NodePath.parse('/Users/koldoon').displayString, '/Users/koldoon');
      expect(NodePath.parse('fs:/Users/koldoon').displayString, '/Users/koldoon');
    });

    test('архив по дороге — просто каталог, и над сервером тоже', () {
      expect(NodePath.parse('/home/a.zip:zip:/inner').displayString, '/home/a.zip/inner');
      expect(
        NodePath.parse('ssh://a@host/etc/backup.zip:zip:/squid').displayString,
        'ssh://a@host/etc/backup.zip/squid',
      );
    });
  });
}
