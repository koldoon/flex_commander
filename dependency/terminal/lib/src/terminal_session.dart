import 'dart:async';
import 'dart:convert';

import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import 'shell_keys.dart';
import 'shell_marks.dart';

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
  TerminalSession.around(
    PtySession pty, {
    int maxLines = defaultMaxLines,
    ProviderLease? lease,
    ShellAgreement? agreement,
  }) : _lease = lease,
       _agreement = agreement,
       terminal = Terminal(maxLines: maxLines) {
    _pty = pty;

    // Свой обработчик впереди стандартного: `xterm` не смотрит на прикладной
    // режим курсорных клавиш, и `mc` не видит стрелок вовсе.
    terminal.inputHandler = CascadeInputHandler([AppCursorKeys(terminal), defaultInputHandler]);

    // Метку разбирает не поток, а сам терминал: она управляющая
    // последовательность, и до текста ей ещё дойти надо. Незнакомый OSC `xterm`
    // отдаёт сюда, нарисовать его он и не пытался.
    terminal.onPrivateOSC = _onPrivateOsc;

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

  /// Уговор с оболочкой; null — сессия без уговора (разовый запуск, тест).
  final ShellAgreement? _agreement;

  /// Последнее, что оболочка сообщила о законченной команде.
  ///
  /// Здесь же, а не в отдельной службе: сообщает о себе сессия, а слушают её
  /// разные — строка ждёт конца своей команды, панель смотрит на каталог.
  ShellMark? get lastMark => _lastMark;
  ShellMark? _lastMark;

  /// Оболочка отметилась. Зовётся перед каждым приглашением — в том числе
  /// первым, ещё до всякой команды.
  void Function(ShellMark mark)? onMark;

  /// Идёт ли команда: между меткой о запуске и следующим приглашением.
  bool get running => _running;
  bool _running = false;

  /// Команда что-то вывела — она сама, а не её отражение.
  ///
  /// От этого зависит, показывать ли экран: молчаливая успешная команда не
  /// должна мигать чёрным. Отличить одно от другого можно только по меткам:
  /// оболочка отражает набранное, и байты приходят всегда.
  ///
  /// Меряется **положением курсора**, а не счётом байтов: метка о запуске
  /// приходит посреди разбора, и в тот миг курсор стоит ровно там, где начнётся
  /// вывод. Сдвинулся к приглашению — значит что-то напечатали.
  bool get commandOutput => _commandOutput;
  bool _commandOutput = false;

  int _outputStart = 0;

  int get _cursorLine => terminal.buffer.absoluteCursorY;

  /// Оболочка о себе рассказывает: уговор подошёл.
  ///
  /// Пока хоть одна метка не пришла, конца команды мы не знаем — и обещать его
  /// нельзя (`spec/single-shell-session.md`, §3).
  bool get marksWork => _marksWork;
  bool _marksWork = false;

  /// Первое приглашение: с него оболочка готова принимать команды.
  ///
  /// Ждать его обязательно. Отправишь команду раньше — и её концом окажется
  /// приглашение, которое оболочка напечатала сама, ещё до неё.
  Future<void> get settled => _settled.future;
  final Completer<void> _settled = Completer<void>();

  /// Оболочку можно **показывать**: уговор заключён и убран с глаз.
  ///
  /// Отличается от [settled] на одну команду. Оболочка отражает всё, что ей
  /// присылают, — и строку уговора тоже; следом уходит `clear`, но между ними
  /// есть кадры, в которые видно чужую кухню. Ждём приглашения **после**
  /// команды: первое приглашение — от уговора, второе — от `clear`.
  Future<void> get ready => _ready.future;
  final Completer<void> _ready = Completer<void>();

  Completer<ShellMark>? _waiting;

  /// Выполнить строку в этой оболочке и дождаться её конца.
  ///
  /// null — оболочка о себе не рассказывает: строка отправлена, но конца её мы
  /// не узнаем, и решать за неё придётся человеку.
  Future<ShellMark>? run(String line) {
    if (!_marksWork) {
      input('$line\n');
      return null;
    }
    final done = Completer<ShellMark>();
    _waiting = done;
    input('$line\n');
    return done.future;
  }

  void _onPrivateOsc(String code, List<String> parts) {
    final mark = _agreement?.parse(code, parts);
    if (mark == null) {
      return;
    }
    switch (mark.kind) {
      case ShellMarkKind.running:
        _running = true;
        _commandOutput = false;
        // Прекратил человек или нет — вопрос про эту команду, а не про сессию:
        // прошлый `Ctrl-C` к новой отношения не имеет.
        _interrupted = false;
        _outputStart = _cursorLine;
      case ShellMarkKind.prompt:
        if (_running && _cursorLine != _outputStart) {
          _commandOutput = true;
        }
        _running = false;
        final waiting = _waiting;
        _waiting = null;
        waiting?.complete(mark);
    }
    _marksWork = true;
    if (!_settled.isCompleted) {
      _settled.complete();
    } else if (mark.kind == ShellMarkKind.prompt && !_ready.isCompleted) {
      _ready.complete();
    }
    _lastMark = mark;
    onMark?.call(mark);
    notifyListeners();
  }

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
    // Считается **по ходу**, а не в конце: экран молчащей команды показывается
    // по первому же её слову, а не когда она уже закончилась.
    if (_running && _cursorLine != _outputStart) {
      _commandOutput = true;
    }
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
    // Ждущих бросать нельзя: оболочка кончилась, ни конца команды, ни готовности
    // больше не будет.
    if (!_settled.isCompleted) {
      _settled.complete();
    }
    if (!_ready.isCompleted) {
      _ready.complete();
    }
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(StateError('Оболочка закрылась'));
    }
    unawaited(_output.cancel());
    // Убить уже мёртвое — не ошибка, а обычный случай: команда из строки
    // обычно кончается сама.
    unawaited(_pty.kill());
    _onExit(_exitCode ?? -1);
    _releaseLease();
    super.dispose();
  }
}
