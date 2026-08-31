import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'terminal_screens.dart';
import 'terminal_session.dart';

/// Постоянная сессия во весь экран.
class TerminalScreenView extends StatelessWidget {
  const TerminalScreenView({super.key, required this.screen});

  final TerminalScreen screen;

  @override
  Widget build(BuildContext context) {
    return _TerminalFrame(
      title: 'Terminal',
      // Выход показан словами, а не клавишей ряда: `F10` внутри принадлежит
      // тому, что там запущено, — `htop` и `mc` им и живут.
      hint: '⌃O panels',
      session: screen.session,
    );
  }
}

/// Работающая (или отработавшая) команда из строки.
class CommandRunView extends StatelessWidget {
  const CommandRunView({super.key, required this.screen});

  final CommandRunScreen screen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: screen,
      builder: (context, _) {
        final code = screen.exitCode;
        return _TerminalFrame(
          title: '\$ ${screen.command}',
          hint: switch (code) {
            null => 'running — ⌃C to interrupt',
            0 => 'done — press any key',
            final failed => 'exit $failed — press any key',
          },
          failed: code != null && code != 0,
          session: screen.session,
        );
      },
    );
  }
}

/// Общая обвязка: шапка с тем, что показано, и сам терминал под ней.
class _TerminalFrame extends StatelessWidget {
  const _TerminalFrame({required this.title, required this.hint, required this.session, this.failed = false});

  final String title;
  final String hint;
  final bool failed;
  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;

    final label = theme.fixedStyle.copyWith(color: colors.pathText);

    return ColoredBox(
      // Фон окна: терминал занимает всё окно и панелью не притворяется.
      color: colors.windowBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: metrics.pathHeaderHeight,
            padding: EdgeInsets.symmetric(horizontal: metrics.panelLeftPadding),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: label)),
                Text(hint, style: label.copyWith(color: failed ? colors.markedBar : colors.secondaryText)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.panelLeftPadding),
              child: TerminalView(
                session.terminal,
                autofocus: true,
                backgroundOpacity: 0,
                // Только железная клавиатура — без подключения к системному
                // текстовому вводу.
                //
                // Иначе на macOS система забирает нажатия себе: `Backspace`
                // уходит в `deleteBackward:` текстового поля, которого у нас
                // нет, и до терминала не доходит вовсе, а буквы приезжают
                // разбором ввода, который на чужой раскладке врёт. Здесь же
                // клавиша приходит как есть: служебные разбирает таблица
                // `xterm` (`Backspace` — `\x7f`, `Tab` — `\x9`, `Ctrl-A` —
                // `\x1`), а печатные берутся из `event.character` — того
                // самого символа, который дала раскладка.
                //
                // Цена — составной ввод (китайский, японский, мёртвые клавиши):
                // в терминале его не будет. Для оболочки это меньшая потеря,
                // чем неработающий `Backspace`.
                hardwareKeyboardOnly: true,
                // С запасными семействами: без них `xterm` подставляет свои,
                // и один и тот же текст в терминале и в строке выходит разными
                // шрифтами.
                textStyle: TerminalStyle(
                  fontFamily: theme.fonts.fixed,
                  fontFamilyFallback: theme.fonts.fixedFallback,
                  fontSize: metrics.fontSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
