import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Программа в псевдотерминале вместе с разбором её вывода.
///
/// Связывает две половины: [PtySession] — сам процесс, [Terminal] из `xterm` —
/// разбор управляющих последовательностей, буфер прокрутки и то, что видно на
/// экране. Обе стороны нужны сразу: программа говорит в буфер, клавиши идут
/// обратно в программу.
///
/// Таких сессий в модуле две породы, и устроены они одинаково: постоянная
/// оболочка под `Ctrl-O` и разовый запуск команды из строки. Разница только в
/// том, кто их заводит и когда убивает.
class TerminalSession extends ChangeNotifier {
  /// Заводит разбор вокруг уже запущенной программы.
  ///
  /// Запускает её [ShellHost] — тот, что у провайдера активной панели: на
  /// локальной панели это `$SHELL` на этой машине, на `ssh://` — оболочка
  /// сервера. Здесь же остаётся то, что от места не зависит: разбор вывода,
  /// буфер прокрутки и обратная дорога для клавиш.
  ///
  /// Размер окна оболочке сообщает вызывающий: он у неё спрашивается **до**
  /// запуска, а буфер разбора заводится здесь.
  TerminalSession.around(PtySession pty, {int maxLines = defaultMaxLines, ProviderLease? lease})
    : _lease = lease,
      terminal = Terminal(maxLines: maxLines) {
    _pty = pty;

    // `allowMalformed` — не небрежность: `cat` на двоичном файле выдаёт что
    // угодно, и падать на этом терминал не вправе.
    _output = _pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(_onOutput);

    terminal.onOutput = _send;
    terminal.onResize = (width, height, _, _) => _pty.resize(columns: width, rows: height);

    unawaited(_pty.exitCode.then(_onExit, onError: (_) => _onExit(-1)));
  }

  /// Сколько строк вывода помнится. Тысяча по умолчанию у `xterm` — мало:
  /// сборка проекта не влезает и в десять.
  static const int defaultMaxLines = 10000;

  /// Что видно на экране и что было до этого.
  final Terminal terminal;

  /// Аренда источника, в котором живёт оболочка; null — своя машина.
  ///
  /// Пока сессия жива, живо и соединение: панель вправе уйти с сервера хоть
  /// сразу, а `htop`, запущенный там, обязан дожить до своего конца. Отпускаем
  /// в двух местах — когда оболочка кончилась сама и когда её закрыли, —
  /// поэтому отпускание одноразовое.
  ProviderLease? _lease;

  void _releaseLease() {
    final lease = _lease;
    _lease = null;
    unawaited(lease?.release());
  }

  late final PtySession _pty;
  late final StreamSubscription<String> _output;

  /// Программа хоть что-то вывела.
  ///
  /// От этого зависит, показывать ли экран разового запуска: молчаливая
  /// успешная команда не должна мигать чёрным (`spec/terminal.md`, §8).
  bool get producedOutput => _producedOutput;
  bool _producedOutput = false;

  /// Человек послал программе `Ctrl-C`.
  ///
  /// Не то же, что «завершилась с ошибкой»: прекратил её он сам, и знать об
  /// этом нужно **до** кода возврата — код у прерванной бывает какой угодно,
  /// от `130` у оболочки до собственного у программы, которая обработала
  /// сигнал по-своему.
  bool get interrupted => _interrupted;
  bool _interrupted = false;

  /// Программа завершилась.
  bool get finished => _exitCode != null;

  /// Код возврата; null — ещё работает.
  int? get exitCode => _exitCode;
  int? _exitCode;

  /// Завершения ждут: разовый запуск решает по нему, что делать с экраном.
  Future<int> get exited => _exited.future;
  final Completer<int> _exited = Completer<int>();

  void _onOutput(String data) {
    _producedOutput = true;
    terminal.write(data);
    notifyListeners();
  }

  void _onExit(int code) {
    if (_exitCode != null) {
      return;
    }
    _exitCode = code;
    // Оболочка кончилась — держать сервер больше незачем.
    _releaseLease();
    if (!_exited.isCompleted) {
      _exited.complete(code);
    }
    notifyListeners();
  }

  /// Отправить программе ввод так, будто его набрали с клавиатуры.
  void input(String data) => _send(data);

  void _send(String data) {
    // `\x03` — не просто байт, а просьба прекратить: разовый запуск по ней
    // решает, что экран больше не нужен (`spec/terminal.md`, §8).
    if (data.contains('\x03')) {
      _interrupted = true;
    }
    _pty.write(utf8.encode(data));
  }

  @override
  void dispose() {
    unawaited(_output.cancel());
    // Убить уже мёртвое — не ошибка, а обычный случай: команда из строки
    // обычно кончается сама.
    unawaited(_pty.kill());
    _onExit(_exitCode ?? -1);
    _releaseLease();
    super.dispose();
  }
}
