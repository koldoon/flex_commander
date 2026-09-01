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
    final lineHeight = _lineHeight(context, theme);

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
              // Снизу — ровно столько, на сколько полоса командной строки выше
              // своей строки текста.
              //
              // Командная строка — тот же терминал, выглядывающий из-под
              // панелей, и её приглашение обязано остаться на месте при
              // `Ctrl-O`. Совпасть должны **строки текста**, а не коробки:
              // текст в полосе стоит по середине, и коробка выступает под ним
              // на половину разницы. Выровняй коробки — и терминал окажется
              // ровно на эту половину ниже.
              //
              // Величина берётся та же, которой полоса и меряется
              // (`commandLineHeight`): подставь сюда высоту поля ввода — и
              // приглашение начнёт прыгать в тот день, когда строке назначат
              // свою высоту.
              padding: EdgeInsets.only(
                left: metrics.panelLeftPadding,
                right: metrics.panelLeftPadding,
                bottom: ((metrics.commandLineHeight - lineHeight) / 2).clamp(0.0, metrics.commandLineHeight),
              ),
              // Сетка прижата к низу, остаток высоты — наверх.
              //
              // Строк у терминала целое число, и остаток есть почти всегда.
              // Лёжа снизу, он уводил последнюю строку вверх на сколько
              // придётся.
              child: _BottomAligned(
                lineHeight: lineHeight,
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
          ),
        ],
      ),
    );
  }

  /// Высота строки терминала — тем же счётом, каким её меряет `xterm`.
  ///
  /// Своим замером, а не заимствованным числом: `xterm` считает её по десятку
  /// букв в том же стиле, и повторить этот счёт надёжнее, чем угадать
  /// произведение кегля на межстрочную — округляет их движок, а не мы.
  static double _lineHeight(BuildContext context, FcTheme theme) {
    final painter = TextPainter(
      text: TextSpan(text: 'mmmmmmmmmm', style: theme.fixedStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

/// Столько строк, сколько влезло целиком, — и прижаты они к низу.
class _BottomAligned extends StatelessWidget {
  const _BottomAligned({required this.lineHeight, required this.child});

  final double lineHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (constraints.maxHeight / lineHeight).floor();
        // Не влезла ни одна — отдаём что есть: пустой терминал хуже кривого.
        if (rows < 1 || !constraints.hasBoundedHeight) {
          return child;
        }
        return Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(width: constraints.maxWidth, height: rows * lineHeight, child: child),
        );
      },
    );
  }
}
