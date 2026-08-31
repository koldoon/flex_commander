import 'dart:async';

import 'package:fc_api/fc_api.dart';

import 'terminal_screens.dart';
import 'terminal_session.dart';
import 'terminal_settings.dart';

/// Выполнить команду во внутреннем терминале — и показать её так, как в
/// приложении принято.
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

  /// [onStarted] зовётся, когда процесс уже пошёл, но ждать его конца ещё
  /// долго: строке в это мгновение пора запомнить команду и очиститься.
  /// Не запустилось — не зовётся вовсе, и набранное остаётся на месте.
  static Future<void> start({
    required Application app,
    required ShellHost host,
    required TerminalSettings options,
    required String command,
    required String workingDirectory,
    Duration showDelay = defaultShowDelay,
    void Function()? onStarted,
  }) async {
    final TerminalSession session;
    try {
      // Чем запускать и как оказаться в нужном каталоге, решает та сторона:
      // на своей машине это `$SHELL` с `-lic`, на сервере — оболочка сервера.
      session = TerminalSession.around(
        await host.run(command, directory: workingDirectory),
        maxLines: options.maxLines,
      );
    } catch (error) {
      // Псевдотерминала на этой платформе может не быть вовсе. Молчать нельзя,
      // но и окна ради этого не ставим: сообщения хватает.
      app.toasts.show('Shell did not start: $error');
      return;
    }

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
      if (session.producedOutput) {
        show();
      }
    }

    session.addListener(onOutput);
    final waiting = Timer(showDelay, () {
      if (!session.finished) {
        show();
      }
    });

    final code = await session.exited;
    waiting.cancel();
    session.removeListener(onOutput);

    // Прервал человек — экран уходит сам, и ждать от него ещё одного нажатия
    // незачем: `Ctrl-C` и было тем нажатием, которым сказали «хватит».
    //
    // Иначе выходил ритуал из двух клавиш: `Ctrl-C` убивал программу, но экран
    // оставался — на нём же и вывод, и `^C`, — а закрывался только следующим
    // `Enter`. Со стороны это читалось как «`Ctrl-C` не сработал».
    if (session.interrupted) {
      if (app.view.positionOf(screen) != null) {
        app.view.popViewportContent(ViewportPosition.fullscreen);
      } else {
        screen.close();
      }
    } else if (session.producedOutput || code != 0) {
      // Сказала хоть слово или провалилась — остаётся до нажатия клавиши.
      show();
    } else if (!shown) {
      // Молча и успешно — экрана не было вовсе.
      screen.close();
    }

    await _reloadPanels(app);
  }

  /// Перечитать панели: команда могла создать, удалить и переименовать что
  /// угодно, и показывать после неё прежний список нельзя.
  ///
  /// Только те, что стоят на настоящей файловой системе: перечитывать `ssh://`
  /// из-за локальной команды — лишний поход по сети.
  static Future<void> _reloadPanels(Application app) async {
    for (final position in const [ViewportPosition.left, ViewportPosition.right]) {
      final panel = app.view.panelAt(position);
      if (panel != null && panel.provider.capabilities.realFileSystem) {
        await panel.reload();
      }
    }
  }
}
