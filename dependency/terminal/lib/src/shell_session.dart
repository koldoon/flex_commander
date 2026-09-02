import 'dart:async';

import 'package:fc_core_api/fc_core_api.dart';

import 'shell_marks.dart';
import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Постоянные сессии оболочки — по одной на место, где они живут.
///
/// Служба, а не поле экрана: экран открывают и закрывают, а оболочка живёт всё
/// время работы приложения.
///
/// **Своя заводится заранее, серверная — по надобности.** Лень была общей и
/// стоила заметного: первый `Ctrl-O` и первая команда ждали запуска оболочки,
/// чтения `.zshrc`, уговора о метках и `clear` — до трёх секунд на тяжёлой
/// настройке, и всё это на глазах. Своя машина ничем за прогрев не платит:
/// процесс один, спит и ничего не делает. Сервер — платит походом по сети и,
/// случается, вопросом о пароле, поэтому его оболочка по-прежнему ждёт, пока
/// её попросят.
///
/// Сессий несколько, потому что мест несколько: своя машина и каждый сервер, на
/// который зашла панель. Ключ — [ShellHost.shellLabel], а не сам провайдер: два
/// соединения к одному серверу должны делить одну оболочку, иначе `Ctrl-O`
/// открывал бы новую всякий раз, когда панель перемонтировали. Локальная —
/// такая же запись в этой таблице, без особого случая.
class ShellSession {
  ShellSession({required this.settings});

  final TerminalSettings Function() settings;

  /// Оболочка сообщила, где она теперь стоит.
  ///
  /// Зовётся на **каждое** приглашение — и после команды из строки, и после
  /// набранной руками в развёрнутом терминале. Что с этим делать, решает не
  /// таблица оболочек: она про сессии, а не про панели.
  void Function(String shellLabel, String directory)? onDirectory;

  /// Сколько ждать первого приглашения от свежей оболочки.
  ///
  /// Ждёт **тот, кто шлёт команду**, а не тот, кто открывает оболочку: `Ctrl-O`
  /// показывает её сразу, пусть и с пустым экраном, а вот команду до первого
  /// приглашения слать нельзя — её концом окажется приглашение, напечатанное
  /// оболочкой самой, ещё до неё.
  ///
  /// Ждать вечно тоже нельзя: оболочка может не понять уговора вовсе. Трёх
  /// секунд хватает и тяжёлому `.zshrc`, и походу по сети до сервера.
  static const Duration settleTimeout = Duration(seconds: 3);

  final Map<String, TerminalSession> _sessions = {};

  /// Оболочку этого места уже запускали.
  bool startedAt(String shellLabel) => _sessions.containsKey(shellLabel);

  /// Хоть какая-то оболочка жива.
  bool get started => _sessions.isNotEmpty;

  /// Сессия этого места; заводит её, если ещё не заводили.
  ///
  /// [directory] — откуда оболочка начнёт, и учитывается он только при первом
  /// запуске: дальше её каталог принадлежит ей самой.
  /// [lease] — аренда источника, в котором живёт оболочка; null — своя машина.
  /// Держит её сессия, а лишнюю — когда оболочка уже была — отпускаем сразу.
  Future<TerminalSession> sessionIn(ShellHost host, String? directory, {ProviderLease? lease}) async {
    final current = _sessions[host.shellLabel];
    if (current != null) {
      // Аренда уже есть у живой сессии: вторая ни к чему, и держать её значило
      // бы не отпустить сервер никогда.
      unawaited(lease?.release());
      return current;
    }

    final PtySession pty;
    try {
      // Открытие ждём: на сервере это поход по сети, и не удаться оно вполне
      // может. Записываем в таблицу только то, что открылось.
      pty = await host.shell(directory: directory);
    } on Object {
      // Не открылось — держать источник нечем и незачем.
      unawaited(lease?.release());
      rethrow;
    }

    // Уговор о метках — первой же строкой в свежую оболочку. Без него конец
    // команды из строки останется незамеченным (`spec/single-shell-session.md`).
    final agreement = ShellAgreement();
    final opened = TerminalSession.around(pty, maxLines: settings().maxLines, lease: lease, agreement: agreement);
    final setup = agreement.setupFor(host.shellProgram);
    if (setup.isNotEmpty) {
      // `clear` следом: сама строка уговора в ленте не нужна, а всё, что после
      // неё, — уже жизнь человека.
      opened.input('$setup\nclear\n');
    }
    // Оболочка смертна: `exit`, `kill`, обрыв `ssh`. Умерла — уходит из
    // таблицы, и следующая команда заводит новую; держать мёртвую значило бы
    // слать команды в никуда.
    final label = host.shellLabel;
    opened.onMark = (mark) {
      if (mark.kind == ShellMarkKind.prompt && mark.directory.isNotEmpty) {
        onDirectory?.call(label, mark.directory);
      }
    };
    unawaited(
      opened.exited.then((_) {
        if (identical(_sessions[label], opened)) {
          _sessions.remove(label);
        }
      }),
    );

    return _sessions[label] = opened;
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
