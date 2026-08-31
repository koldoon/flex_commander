import 'package:fc_api/fc_api.dart';

import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Постоянные сессии оболочки — по одной на место, где они живут.
///
/// Служба, а не поле экрана: экран открывают и закрывают, а оболочка живёт всё
/// время работы приложения. Заводится **лениво**, при первом `Ctrl-O`:
/// приложение, в котором терминал ни разу не открывали, лишнего процесса не
/// держит.
///
/// Сессий несколько, потому что мест несколько: своя машина и каждый сервер, на
/// который зашла панель. Ключ — [ShellHost.shellLabel], а не сам провайдер: два
/// соединения к одному серверу должны делить одну оболочку, иначе `Ctrl-O`
/// открывал бы новую всякий раз, когда панель перемонтировали. Локальная —
/// такая же запись в этой таблице, без особого случая.
class ShellSession {
  ShellSession({required this.settings});

  final TerminalSettings Function() settings;

  final Map<String, TerminalSession> _sessions = {};

  /// Оболочку этого места уже запускали.
  bool startedAt(String shellLabel) => _sessions.containsKey(shellLabel);

  /// Хоть какая-то оболочка жива.
  bool get started => _sessions.isNotEmpty;

  /// Сессия этого места; заводит её, если ещё не заводили.
  ///
  /// [directory] — откуда оболочка начнёт, и учитывается он только при первом
  /// запуске: дальше её каталог принадлежит ей самой.
  Future<TerminalSession> sessionIn(ShellHost host, String? directory) async {
    final current = _sessions[host.shellLabel];
    if (current != null) {
      return current;
    }

    // Открытие ждём: на сервере это поход по сети, и не удаться оно вполне
    // может. Записываем в таблицу только то, что открылось.
    final opened = TerminalSession.around(await host.shell(directory: directory), maxLines: settings().maxLines);
    return _sessions[host.shellLabel] = opened;
  }

  /// Место закрылось — закрылась и его оболочка.
  ///
  /// Зовётся, когда уходит провайдер: держать сессию сервера, с которого уже
  /// ушли, незачем — она всё равно оборвана.
  void closeAt(String shellLabel) {
    _sessions.remove(shellLabel)?.dispose();
  }

  /// Приложение уходит — уходят и все оболочки.
  void close() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}
