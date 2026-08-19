import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:fc_api/fc_api.dart';

import 'dartssh_sftp.dart';
import 'sftp_api.dart';
import 'ssh_address.dart';
import 'ssh_authenticator.dart';

/// Живое соединение с сервером: канал SFTP и дом пользователя на той стороне.
class SshConnection {
  SshConnection._(this._client, this.sftp, this.homePath);

  final SSHClient _client;

  /// Чем работать с деревом на той стороне.
  final SftpApi sftp;

  /// Домашний каталог пользователя на сервере — куда открывается панель.
  final String homePath;

  /// Подключается и входит на сервер.
  ///
  /// Порядок способов — как у обычного клиента, но вопросы задаются только
  /// тогда, когда без них не обойтись:
  ///
  /// 1. ключи, открывшиеся без фразы, — молча;
  /// 2. если сервер их не принял — ключи под фразой (её спрашивают) и пароль;
  ///
  /// Из-за этого попыток подключения может быть две. Это дешевле, чем вопрос о
  /// парольной фразе при каждом входе на сервер, который и так пускает по
  /// открытому ключу.
  static Future<SshConnection> open({
    required SshTarget target,
    required Credentials credentials,
    String? sshDirectory,
    Duration timeout = const Duration(seconds: 20),
    SshKeyring? keyring,
  }) async {
    final keys = keyring ?? await SshKeyring.read(sshDirectory ?? SshKeyring.defaultDirectory());

    if (keys.ready.isNotEmpty) {
      try {
        return await _connect(target: target, identities: keys.ready, credentials: null, timeout: timeout);
      } on _KeysRejected {
        // Сервер открытым ключам не поверил — дальше со всем остальным.
      }
    }

    final identities = [...keys.ready, ...await keys.unlock(credentials)];
    return await _connect(target: target, identities: identities, credentials: credentials, timeout: timeout);
  }

  Future<void> close() async {
    await sftp.close();
    _client.close();
    await _client.done;
  }

  /// Одна попытка входа.
  ///
  /// [credentials] == null — проход без вопросов: пароль не спрашивается, и
  /// отказ сервера означает «эти ключи не подошли», а не «не пустили».
  static Future<SshConnection> _connect({
    required SshTarget target,
    required List<SSHKeyPair> identities,
    required Credentials? credentials,
    required Duration timeout,
  }) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(target.host, target.port, timeout: timeout);
    } on SocketException catch (error) {
      throw FsError(target.display, FsErrorKind.io, error);
    }

    final asker = credentials == null ? null : _PasswordAsker(target, credentials);

    final client = SSHClient(
      socket,
      username: target.user,
      identities: identities.isEmpty ? null : identities,
      onPasswordRequest: asker?.ask,
      // Ключ хоста принимается без проверки. Это долг, а не решение:
      // `known_hosts` — отдельная работа со своим окном подтверждения, и
      // сделанная наполовину она хуже, чем не сделанная вовсе.
      disableHostkeyVerification: true,
    );

    try {
      await client.authenticated;
      final sftp = DartsshSftp(await client.sftp());
      // Дом спрашивается один раз: `.` для SFTP — это каталог, в который
      // сервер сажает пользователя после входа.
      final home = await sftp.absolute('.');
      return SshConnection._(client, sftp, home);
    } on Object catch (error) {
      client.close();
      if (error is SSHAuthError) {
        if (credentials == null) {
          throw const _KeysRejected();
        }
        // Отказ отвечать — тоже отказ в доступе: сказать больше нечего.
        throw FsError(target.display, FsErrorKind.permissionDenied, error);
      }
      if (error is FsError) {
        rethrow;
      }
      throw FsError(target.display, FsErrorKind.io, error);
    }
  }
}

/// Сервер спрашивает пароль — спрашиваем человека.
///
/// `dartssh2` зовёт обработчик заново на каждую неудачную попытку, поэтому
/// повтор виден отсюда: прошлый ответ забывается, а окно говорит, что он не
/// подошёл, вместо того чтобы молча спросить то же самое.
class _PasswordAsker {
  _PasswordAsker(SshTarget target, this._credentials)
    : _request = CredentialRequest(realm: target.realm, title: 'SSH authentication', message: target.display),
      _fromAddress = target.passwordFromAddress;

  final Credentials _credentials;

  CredentialRequest _request;
  String? _fromAddress;
  bool _asked = false;

  Future<String?> ask() async {
    final fromAddress = _fromAddress;
    if (fromAddress != null) {
      // Пароль из адреса — это уже ответ, спрашивать его второй раз незачем.
      _fromAddress = null;
      return fromAddress;
    }

    if (_asked) {
      _credentials.forget(_request.realm);
      _request = _request.retrying();
    }
    _asked = true;

    return (await _credentials.obtain(_request))?.password;
  }
}

/// Ключи не подошли — не повод сдаваться, а повод спросить.
class _KeysRejected implements Exception {
  const _KeysRejected();
}
