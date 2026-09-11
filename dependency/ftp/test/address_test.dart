import 'package:fc_ftp/fc_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор адреса сервера.
void main() {
  FtpTarget parse(String address) => FtpTarget.parse(Uri.parse(address));

  test('без пользователя вход анонимный', () {
    // У ssh «без пользователя» значит «под собой»; у FTP учётной записи на
    // чужом сервере нет вовсе, зато есть анонимный вход.
    final target = parse('ftp://ftp.example.org/pub');

    expect(target.user, FtpTarget.anonymous);
    expect(target.isAnonymous, isTrue);
    expect(target.host, 'ftp.example.org');
    expect(target.port, 21);
    expect(target.path, '/pub');
    expect(target.secure, isFalse);
  });

  test('пользователь и порт берутся из адреса', () {
    final target = parse('ftp://koldoon@ftp.example.org:2121/srv');

    expect(target.user, 'koldoon');
    expect(target.isAnonymous, isFalse);
    expect(target.port, 2121);
    expect(target.authority, '//koldoon@ftp.example.org:2121');
    expect(target.display, 'koldoon@ftp.example.org:2121');
  });

  test('порт по умолчанию в путь не пишется', () {
    // Иначе один и тот же сервер выглядел бы по-разному в зависимости от
    // того, как его набрали.
    expect(parse('ftp://u@host:21/').authority, '//u@host');
    expect(parse('ftp://u@host/').authority, '//u@host');
  });

  test('ftps — это шифрование, и решает схема', () {
    expect(parse('ftps://host/').secure, isTrue);
    expect(parse('ftp://host/').secure, isFalse);
    expect(parse('FTPS://host/').secure, isTrue);
  });

  test('пароль из адреса в путь не попадает', () {
    final target = parse('ftp://koldoon:secret@host/pub');

    expect(target.passwordFromAddress, 'secret');
    expect(target.authority, '//koldoon@host');
    expect(target.authority, isNot(contains('secret')));
    expect(target.realm, isNot(contains('secret')));
    expect(target.display, isNot(contains('secret')));
  });

  test('область помнит и схему, и порт', () {
    expect(parse('ftp://u@host/').realm, 'ftp:u@host:21');
    expect(parse('ftps://u@host:990/').realm, 'ftps:u@host:990');
  });

  test('начало пути отрезается, а обычный путь не трогается', () {
    final target = parse('ftp://u@host/');

    expect(target.stripAuthority('//u@host/pub/x'), '/pub/x');
    expect(target.stripAuthority('//u@host'), '/');
    expect(target.stripAuthority('/pub/x'), '/pub/x');
  });

  test('имя пользователя с собакой разбирается', () {
    // На хостингах это обычное имя: `ftp://user%40site.ru@ftp.host/`.
    expect(parse('ftp://user%40site.ru@ftp.host/').user, 'user@site.ru');
  });
}
