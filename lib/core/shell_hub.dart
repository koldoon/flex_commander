import 'dart:async';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'panel_session.dart';

/// Оболочки — по одной на место, где они живут.
///
/// Живут они здесь, а не у экрана, и причина не в изоляте. Оболочка — это
/// процесс и соединение: `htop`, запущенный на сервере, обязан дожить до своего
/// конца, даже если панель ушла оттуда сразу, — а держит соединение аренда, и
/// аренда бывает только по эту сторону. Экрану достаётся то, что и должно:
/// разбор вывода, лента прокрутки и клавиши обратно
/// (`docs/spec/client-server.md`, §5.1.5).
///
/// Мест несколько — своя машина и каждый сервер, куда зашла панель, — а
/// оболочка на месте одна: два соединения к одному серверу делят её, иначе
/// `Ctrl-O` заводил бы новую всякий раз, когда панель перемонтировали. Ключ —
/// [ShellHost.shellLabel]; локальная оболочка такая же запись в этой таблице,
/// без особого случая.
class ShellHub {
  ShellHub({
    required FcServices services,
    required PanelSession Function(PanelId panel) sessionOf,
    required void Function(CoreEvent event) say,
  }) : _services = services,
       _sessionOf = sessionOf,
       _say = say;

  final FcServices _services;
  final PanelSession Function(PanelId panel) _sessionOf;
  final void Function(CoreEvent event) _say;

  final Map<String, _Shell> _shells = {};

  /// Оболочка этого места; заводит её, если ещё не заводили.
  ///
  /// Отказ уходит бедой: клавишу нажали, и сказать, почему ничего не вышло,
  /// обязательно — псевдотерминала на этой платформе может не быть вовсе, а на
  /// сервере открытие канала это поход по сети.
  Future<CoreReply> open(OpenShell request) async {
    final host = _hostFor(request.panel);
    if (host == null) {
      return const CoreFailed(FsError('', FsErrorKind.notSupported));
    }

    final label = host.shellLabel;
    final runId = idOf(label);
    final current = _shells[label];
    if (current != null) {
      return ShellOpened(runId, label: label, program: host.shellProgram ?? '', fresh: false);
    }

    // Аренда берётся **до** запуска и живёт столько же, сколько оболочка: уйти
    // с сервера панель вправе хоть сразу.
    final lease = request.panel == null ? null : _sessionOf(request.panel!).leaseProvider();
    final PtySession pty;
    try {
      pty = await host.shell(directory: request.directory, columns: request.columns, rows: request.rows);
    } on FsError catch (error) {
      unawaited(lease?.release());
      return CoreFailed(error);
    } on Object catch (error) {
      unawaited(lease?.release());
      return CoreFailed(FsError(error.toString(), FsErrorKind.notSupported));
    }

    final shell = _Shell(pty, lease);
    _shells[label] = shell;
    shell.output = pty.output.listen((bytes) => _say(ShellOutput(runId, bytes)));
    unawaited(pty.exitCode.then((code) => _exited(label, runId, code), onError: (_) => _exited(label, runId, -1)));

    return ShellOpened(runId, label: label, program: host.shellProgram ?? '', fresh: true);
  }

  /// Сказать в оболочку: ввод, размер окна, «хватит».
  ///
  /// Молча мимо неизвестного имени: оболочка смертна, а клавиша, нажатая в тот
  /// же миг, — обычное дело, а не ошибка.
  bool tell(String runId, OperationInput input) {
    final shell = _shells[_labelOf(runId)];
    if (shell == null) {
      return false;
    }
    switch (input) {
      case ShellInput(:final bytes):
        shell.pty.write(Uint8List.fromList(bytes));
      case ShellResize(:final columns, :final rows):
        shell.pty.resize(columns: columns, rows: rows);
      case CancelInput():
        unawaited(shell.pty.kill());
      case OperationInput():
        return false;
    }
    return true;
  }

  /// Приложение уходит — уходят и все оболочки.
  void dispose() {
    for (final shell in _shells.values.toList()) {
      shell.close();
    }
    _shells.clear();
  }

  /// Имя разговора по месту — и обратно.
  ///
  /// Считается, а не раздаётся счётчиком: оболочка одна на место, и второе имя
  /// означало бы вторую оболочку.
  static String idOf(String shellLabel) => 'shell@$shellLabel';

  static String _labelOf(String runId) => runId.startsWith('shell@') ? runId.substring(6) : '';

  void _exited(String label, String runId, int code) {
    final shell = _shells.remove(label);
    shell?.close();
    _say(ShellExited(runId, code));
  }

  /// Где выполнять: у панели — её источник, без панели — своя машина.
  ///
  /// Без панели греют оболочку заранее, когда панелей ещё нет вовсе. Своя
  /// машина берётся службой: её объявляет модуль локальной файловой системы, и
  /// без него греть просто нечего.
  ShellHost? _hostFor(PanelId? panel) {
    if (panel == null) {
      return _services.resolveAll<ShellHost>().firstOrNull;
    }
    final provider = _sessionOf(panel).directory?.provider;
    return provider is ShellHost ? provider as ShellHost : null;
  }
}

/// Одна живая оболочка: сам процесс, подписка на его вывод и аренда места.
class _Shell {
  _Shell(this.pty, this.lease);

  final PtySession pty;
  ProviderLease? lease;
  StreamSubscription<Uint8List>? output;

  void close() {
    unawaited(output?.cancel());
    output = null;
    // Убить уже мёртвое — не ошибка, а обычный случай: оболочку закрывают
    // `exit`.
    unawaited(pty.kill());
    final held = lease;
    lease = null;
    unawaited(held?.release());
  }
}
