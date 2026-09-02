import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter/foundation.dart';

/// Реализация [Elevation]: спрашивает согласие, берёт пароль и зовёт `sudo`.
///
/// Выполняет она **через оболочку той стороны** ([ShellHost]) — ту самую, что
/// открывает `Ctrl-O`. Отсюда и главное свойство: разницы между «повысить
/// здесь» и «повысить на сервере» в коде нет, она целиком в том, какой хост ей
/// дали.
///
/// Псевдотерминал выбран не случайно: `sudo` спрашивает пароль у `/dev/tty`, а
/// не из обычного ввода, — и именно поэтому запуск программ ([ProcessRunner])
/// для этого не годится.
class ElevationController extends ChangeNotifier implements Elevation {
  ElevationController({required Credentials credentials, required bool Function() allowed})
    : _credentials = credentials,
      _allowed = allowed;

  final Credentials _credentials;
  final bool Function() _allowed;

  ElevationRequest? _pending;
  Completer<bool>? _answer;

  @override
  bool get enabled => _allowed();

  @override
  ElevationRequest? get pending => _pending;

  @override
  Future<bool> copyOver({
    required ShellHost host,
    required String temporary,
    required String target,
    required ElevationRequest about,
  }) async {
    if (!enabled) {
      return false;
    }

    // Согласие спрашивается **всегда**, даже когда пароль не нужен: запомненный
    // ответ или `NOPASSWD` не должны превращать запись в системный каталог в
    // незаметное действие.
    if (!await _agreed(about)) {
      return false;
    }

    final needsPassword = !await _run(host, 'sudo -n true');
    if (!needsPassword) {
      return _copy(host, temporary, target, null);
    }

    var request = CredentialRequest(
      realm: about.realm,
      title: 'Administrator rights',
      message: '${about.action} ${about.path} on ${about.where} as administrator',
    );

    // Повтор — забота спрашивающего: только он знает, подошёл ли пароль.
    for (var attempt = 0; attempt < 2; attempt++) {
      final credential = await _credentials.obtain(request);
      if (credential == null) {
        // Отказались отвечать: цель не тронута.
        return false;
      }
      if (await _copy(host, temporary, target, credential.password)) {
        return true;
      }
      _credentials.forget(request.realm);
      request = request.retrying();
    }

    throw FsError(target, FsErrorKind.permissionDenied);
  }

  @override
  void answer(bool agreed) {
    final waiting = _answer;
    if (waiting == null) {
      return;
    }
    _pending = null;
    _answer = null;
    waiting.complete(agreed);
    notifyListeners();
  }

  Future<bool> _agreed(ElevationRequest about) {
    _pending = about;
    final answer = _answer = Completer<bool>();
    notifyListeners();
    return answer.future;
  }

  /// Копирование от администратора.
  ///
  /// `cp`, а не переименование: файл, переименованный от `root`, достался бы
  /// `root` и потерял исходные права. `--` перед путями обязательно — файл с
  /// именем `-rf` иначе стал бы ключом.
  Future<bool> _copy(ShellHost host, String temporary, String target, String? password) {
    final command = 'sudo -S -p "" cp -- ${_quote(temporary)} ${_quote(target)}';
    return _run(host, command, password: password);
  }

  /// Выполнить и сказать, вышло ли.
  ///
  /// Пароль уходит **записью в псевдотерминал**, а не аргументом: аргументы
  /// видно в `ps` всей машине.
  Future<bool> _run(ShellHost host, String command, {String? password}) async {
    final PtySession session;
    try {
      session = await host.run(command);
    } on Object {
      return false;
    }

    // Вывод читаем и выбрасываем: программа, чей вывод никто не забирает,
    // встанет на заполненном канале и не кончится никогда.
    final drained = session.output.drain<void>();

    if (password != null) {
      session.write(Uint8List.fromList(utf8.encode('$password\n')));
    }

    final code = await session.exitCode;
    await drained;
    return code == 0;
  }

  /// Путь в кавычках для оболочки.
  ///
  /// Одинарные кавычки не толкуются вовсе — кроме самих себя, и закрыть их
  /// ради одной кавычки приходится по всем правилам: `'\''`.
  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  @override
  void dispose() {
    // Незаконченный вопрос закрывается отказом: иначе тот, кто ждёт ответа,
    // остался бы висеть навсегда.
    _answer?.complete(false);
    _answer = null;
    _pending = null;
    super.dispose();
  }
}
