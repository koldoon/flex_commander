import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

/// Ключи пользователя из `~/.ssh`.
///
/// Разделены надвое нарочно: ключ без парольной фразы можно предложить серверу
/// молча, а за ключом под фразой стоит вопрос человеку. Спрашивать фразу, пока
/// не выяснилось, что без неё не обойтись, — это вопрос впустую при каждом
/// подключении.
class SshKeyring {
  const SshKeyring({required this.ready, required this.locked});

  const SshKeyring.empty() : ready = const [], locked = const [];

  /// Имена, которые пробует обычный клиент, в том же порядке предпочтения.
  static const List<String> fileNames = ['id_ed25519', 'id_ecdsa', 'id_rsa'];

  /// Каталог ключей текущего пользователя.
  static String defaultDirectory() {
    final home = Platform.environment['HOME'];
    return home == null || home.isEmpty ? p.join(Directory.current.path, '.ssh') : p.join(home, '.ssh');
  }

  /// Читает ключи из каталога. Отсутствующего каталога достаточно: остаётся
  /// пароль, и это рабочий случай, а не ошибка.
  static Future<SshKeyring> read(String directory) async {
    final ready = <SSHKeyPair>[];
    final locked = <String>[];

    for (final name in fileNames) {
      final file = File(p.join(directory, name));
      String pem;
      try {
        if (!await file.exists()) {
          continue;
        }
        pem = await file.readAsString();
      } on IOException {
        // Ключ есть, но прочитать его нельзя — пойдём дальше: чужие права на
        // файл не повод не пустить человека на сервер вовсе.
        continue;
      }

      try {
        if (SSHKeyPair.isEncryptedPem(pem)) {
          locked.add(file.path);
        } else {
          ready.addAll(SSHKeyPair.fromPem(pem));
        }
      } on Object {
        // Не ключ или ключ незнакомого вида. Молча мимо: в `~/.ssh` у
        // человека может лежать что угодно, и падать из-за этого нельзя.
        // Именно `Object`: библиотека отвечает то `SSHError`, то
        // `FormatException` — по тому, на каком шаге разбора она споткнулась.
        continue;
      }
    }

    return SshKeyring(ready: ready, locked: locked);
  }

  /// Ключи, открывшиеся сами.
  final List<SSHKeyPair> ready;

  /// Пути к ключам под парольной фразой.
  final List<String> locked;

  bool get isEmpty => ready.isEmpty && locked.isEmpty;

  /// Сколько раз спрашивать фразу к одному ключу, прежде чем считать, что
  /// человек её не помнит.
  static const int _attempts = 3;

  /// Открывает ключи под фразой, спрашивая её тем же окном, что и пароль
  /// архива.
  ///
  /// Область запоминания — сам файл ключа, а не сервер: один ключ ходит на
  /// много серверов, и фраза у него одна на всех.
  Future<List<SSHKeyPair>> unlock(Credentials credentials) async {
    final unlocked = <SSHKeyPair>[];

    for (final path in locked) {
      final String pem;
      try {
        pem = await File(path).readAsString();
      } on IOException {
        continue;
      }

      var request = CredentialRequest(realm: 'ssh-key:$path', title: 'Encrypted key', message: p.basename(path));

      for (var attempt = 0; attempt < _attempts; attempt++) {
        final passphrase = (await credentials.obtain(request))?.password;
        if (passphrase == null || passphrase.isEmpty) {
          // Человек отказался открывать этот ключ — остаются остальные
          // способы, а не отказ в подключении.
          break;
        }

        try {
          unlocked.addAll(SSHKeyPair.fromPem(pem, passphrase));
          break;
        } on SSHKeyDecryptError {
          // Фраза не подошла: забыть, иначе следующий вопрос вернёт её же.
          credentials.forget(request.realm);
          request = request.retrying();
        } on Object {
          // Ключ испорчен — фраза здесь ни при чём, спрашивать её снова
          // бессмысленно.
          break;
        }
      }
    }

    return unlocked;
  }
}
