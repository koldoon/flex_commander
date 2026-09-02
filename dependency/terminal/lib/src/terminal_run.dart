import 'dart:async';

import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'shell_command.dart';
import 'shell_session.dart';
import 'terminal_screens.dart';
import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Выполнить команду в оболочке — и показать её так, как в приложении принято.
///
/// Оболочка **одна на место** и та же, что под `Ctrl-O`: команда уходит в неё
/// строкой, а не запускается своим процессом. Отсюда и история — всё, что
/// запускали, лежит в одной ленте (`spec/single-shell-session.md`).
///
/// Общее место для двух команд: набранной в строке (`terminal.run`) и запуска
/// файла под курсором (`terminal.runNode`). Запускается всё одинаково — своим
/// процессом, в заданном каталоге, оболочкой человека, — и показывается тоже
/// одинаково; разное у них только то, откуда взялась строка.
///
/// Второй копии этих правил нарочно нет: они уже менялись (задержка показа,
/// молчаливый успех, перечитывание панелей) и будут меняться дальше, а две
/// почти одинаковые копии расходятся в первую же правку.
class TerminalRun {
  /// Сколько ждать, прежде чем показать экран молчащей команды.
  ///
  /// Молчаливая и быстрая (`mkdir`, `chmod`) не должна мигать чёрным вовсе, а
  /// молчаливая и долгая (`sleep`, `make -s`) не должна выглядеть как «ничего
  /// не произошло».
  static const Duration defaultShowDelay = Duration(milliseconds: 300);

  /// [onStarted] зовётся, когда команда уже ушла в оболочку: строке в это
  /// мгновение пора запомнить её и очиститься. Не ушла — не зовётся вовсе, и
  /// набранное остаётся на месте.
  static Future<void> start({
    required Application app,
    required ShellSession shells,
    required ShellHost host,
    required TerminalSettings options,
    required String command,
    required String workingDirectory,
    ProviderLease? lease,
    Duration showDelay = defaultShowDelay,
    void Function()? onStarted,
  }) async {
    final TerminalSession session;
    try {
      session = await shells.sessionIn(host, workingDirectory, lease: lease);
    } catch (error) {
      unawaited(lease?.release());
      // Псевдотерминала на этой платформе может не быть вовсе. Молчать нельзя,
      // но и окна ради этого не ставим: сообщения хватает.
      app.toasts.show('Shell did not start: $error');
      return;
    }

    // До первого приглашения команду слать нельзя: её концом окажется
    // приглашение, напечатанное оболочкой самой.
    await session.ready.timeout(ShellSession.settleTimeout, onTimeout: () {});

    if (session.running) {
      // Вторая строка ушла бы не в приглашение, а на ввод работающей
      // программы, и человек этого не увидел бы вовсе.
      app.toasts.show('The shell is busy');
      return;
    }

    final done = session.run(_lineFor(session, command, workingDirectory));
    onStarted?.call();

    final screen = CommandRunScreen(command: command, session: session);

    var shown = false;
    void show() {
      if (shown) {
        return;
      }
      shown = true;
      app.view.pushViewportContent(ViewportPosition.fullscreen, screen);
    }

    void onOutput() {
      if (session.commandOutput) {
        show();
      }
    }

    session.addListener(onOutput);
    final waiting = Timer(showDelay, () {
      if (!screen.finished) {
        show();
      }
    });

    // Метки нет — конца команды мы не узнаем: экран показывается и ждёт
    // клавиши, а решает человек (`spec/single-shell-session.md`, §3).
    if (done == null) {
      waiting.cancel();
      session.removeListener(onOutput);
      show();
      return;
    }

    int code;
    try {
      code = (await done).exitCode;
    } on Object {
      // Оболочка закрылась посреди команды: конца у неё нет, и молчать об этом
      // нельзя.
      code = -1;
    }
    screen.finish(code);
    waiting.cancel();
    session.removeListener(onOutput);

    // Прервал человек — экран уходит сам, и ждать от него ещё одного нажатия
    // незачем: `Ctrl-C` и было тем нажатием, которым сказали «хватит».
    //
    // Иначе выходил ритуал из двух клавиш: `Ctrl-C` убивал программу, но экран
    // оставался — на нём же и вывод, и `^C`, — а закрывался только следующим
    // `Enter`. Со стороны это читалось как «`Ctrl-C` не сработал».
    void hide() {
      if (app.view.positionOf(screen) != null) {
        app.view.popViewportContent(ViewportPosition.fullscreen);
      } else {
        screen.close();
      }
    }

    if (session.interrupted) {
      hide();
    } else if (code == 0 && options.afterCommand == TerminalSettings.hideAfterCommand) {
      // Успешная — уходит сама, если так велели. Провалившаяся ждёт клавиши
      // всегда: код возврата — единственное, о чём точно нужно сказать.
      hide();
    } else if (session.commandOutput || code != 0) {
      // Сказала хоть слово или провалилась — остаётся до нажатия клавиши.
      show();
    } else if (!shown) {
      // Молча и успешно — экрана не было вовсе.
      screen.close();
    }

    // Панель, которая сейчас уходит за оболочкой, перечитывать не надо — и
    // нельзя: переход уже начался, а перечитывание его отменит и вернёт на
    // прежнее место. Сам переход и есть перечитывание, только нового каталога.
    final moved = session.lastMark?.directory;
    await _reloadPanels(app, skip: moved != null && moved != workingDirectory ? app.activePanel : null);
  }

  /// Строка, которая уйдёт в оболочку.
  ///
  /// Каталог досылается **только когда разошёлся**: оболочка одна, и гонять её
  /// туда-сюда на каждую команду незачем. Где она стоит, известно точно — из
  /// метки; не известно вовсе (метки нет) — досылаем на всякий случай.
  static String _lineFor(TerminalSession session, String command, String directory) {
    final at = session.lastMark?.directory;
    if (at == directory) {
      return command;
    }
    return 'cd ${ShellCommand.quote(directory)} && $command';
  }

  /// Перечитать панели: команда могла создать, удалить и переименовать что
  /// угодно, и показывать после неё прежний список нельзя.
  ///
  /// Только те, что стоят на настоящей файловой системе: перечитывать `ssh://`
  /// из-за локальной команды — лишний поход по сети.
  static Future<void> _reloadPanels(Application app, {Panel? skip}) async {
    for (final position in const [ViewportPosition.left, ViewportPosition.right]) {
      final panel = app.view.panelAt(position);
      if (panel != null && panel != skip && panel.source.capabilities.realFileSystem) {
        await panel.reload();
      }
    }
  }
}
