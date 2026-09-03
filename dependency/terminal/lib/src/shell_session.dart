import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'shell_marks.dart';
import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Постоянные сессии оболочки — по одной на место, где они живут.
///
/// Служба, а не поле экрана: экран открывают и закрывают, а оболочка живёт всё
/// время работы приложения.
///
/// Сама оболочка живёт **в ядре**: там псевдотерминал и там же аренда места —
/// `htop`, запущенный на сервере, обязан дожить до своего конца, даже если
/// панель ушла оттуда сразу. Здесь остаётся то, что принадлежит экрану: разбор
/// вывода, лента прокрутки и клавиши обратно
/// (`docs/spec/client-server.md`, §5.1.5).
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

  /// Сессия того места, где стоит панель; заводит её, если ещё не заводили.
  ///
  /// [panel] null — своя машина: так её греют заранее, когда панелей ещё нет.
  /// [directory] — откуда оболочка начнёт, и учитывается он только при первом
  /// запуске: дальше её каталог принадлежит ей самой.
  ///
  /// Аренды здесь больше нет: место держит ядро, пока жива оболочка.
  Future<TerminalSession> sessionIn(Application app, {Panel? panel, String? directory}) async {
    // Ждём: на сервере открытие канала — поход по сети, и не удаться оно
    // вполне может. Отказ уходит бедой тому, кто просил.
    final channel = await app.openShell(panel: panel, directory: directory);
    final label = channel.label;
    final current = _sessions[label];
    if (current != null) {
      return current;
    }

    // Уговор о метках — первой же строкой в свежую оболочку. Без него конец
    // команды из строки останется незамеченным (`spec/single-shell-session.md`).
    // Уже жившей второй раз не шлём: она о себе и так рассказывает, а лишняя
    // строка встала бы поперёк того, что человек в ней делает.
    final agreement = ShellAgreement();
    final opened = TerminalSession.around(channel.pty, maxLines: settings().maxLines, agreement: agreement);
    final setup = channel.fresh ? agreement.setupFor(channel.program.isEmpty ? null : channel.program) : '';
    if (setup.isNotEmpty) {
      // `clear` следом: сама строка уговора в ленте не нужна, а всё, что после
      // неё, — уже жизнь человека.
      opened.input('$setup\nclear\n');
    }
    // Оболочка смертна: `exit`, `kill`, обрыв `ssh`. Умерла — уходит из
    // таблицы, и следующая команда заводит новую; держать мёртвую значило бы
    // слать команды в никуда.
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
