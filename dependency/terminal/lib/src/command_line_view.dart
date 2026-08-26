import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'command_line_state.dart';

/// Строка под панелями: приглашение и ввод.
///
/// Системный фокус здесь идёт **следом** за владельцем ввода, а не вместо
/// него: кому принадлежат клавиши, решает `activeArea` (`spec/terminal.md`,
/// §5), и поле просит фокус тогда, когда область уже стала активной. Иначе два
/// состояния разъедутся — курсор мигает в строке, а буквы уходят в панель.
class CommandLineView extends StatefulWidget {
  const CommandLineView({super.key, required this.state});

  final CommandLineState state;

  @override
  State<CommandLineView> createState() => _CommandLineViewState();
}

class _CommandLineViewState extends State<CommandLineView> {
  final FocusNode _node = FocusNode(debugLabel: 'command line');

  ApplicationView get view => widget.state.app.view;

  @override
  void initState() {
    super.initState();
    view.addListener(_syncFocus);
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    view.removeListener(_syncFocus);
    _node.removeListener(_onFocusChanged);
    _node.dispose();
    super.dispose();
  }

  /// Курсор и ввод должны быть в одном месте.
  ///
  /// Правило простое и работает в обе стороны, потому что человек судит о
  /// происходящем по курсору, а не по нашему состоянию:
  ///
  /// * **фокус ушёл из поля, а ввод числится за строкой** — значит его забрали
  ///   мимо нас (окно команды, чужой виджет, сам `TextField` по `Enter`).
  ///   Курсора нет, человек справедливо считает, что вернулся в панель, — и
  ///   если ввод не отпустить, панельные клавиши молчат до самого `Esc`;
  /// * **фокус пришёл в поле, а ввод у панели** — значит его отдали нам:
  ///   закрылось окно команды и вернуло фокус туда, откуда забрало, или человек
  ///   ткнул в строку мышью. Курсор мигает — пусть и клавиши будут здесь.
  void _onFocusChanged() {
    if (!mounted || _node.hasFocus == (view.activeArea == ViewportPosition.bottom)) {
      return;
    }

    if (_node.hasFocus) {
      // Пока открыто окно, клавиши принадлежат ему целиком, и забирать ввод не
      // за чем: фокус ещё вернётся, когда окно закроется.
      if (view.dialogs.isEmpty) {
        view.setFocus(ViewportPosition.bottom);
      }
      return;
    }

    // Окно ушло к соседнему приложению — фокус стал ничьим. Это не «фокус
    // забрали», и выводить из строки по этому поводу нельзя: человек вернётся
    // и продолжит набирать. Признак тот же, что у обработчика клавиатуры.
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus is FocusScopeNode) {
      return;
    }

    final panel = widget.state.panel;
    if (panel != null) {
      widget.state.app.activate(panel);
    }
  }

  void _syncFocus() {
    final mine = view.activeArea == ViewportPosition.bottom;
    if (mine && !_node.hasFocus) {
      _node.requestFocus();
    } else if (!mine && _node.hasFocus) {
      _node.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final state = widget.state;

    return ListenableBuilder(
      // Поле тоже: подсказка дополнения уходит от любой правки строки, а о
      // правке знает только контроллер текста.
      listenable: Listenable.merge([state, view, state.panel, state.text]),
      builder: (context, _) {
        final enabled = state.enabled;
        final style = TextStyle(
          fontFamily: theme.fonts.fixed,
          fontSize: metrics.fontSize,
          color: enabled ? colors.rowText : colors.secondaryText,
        );

        // Ряд подсказок стоит **всегда**, даже когда он пуст.
        //
        // `if` здесь менял бы строение дерева, а вместе с ним и поле ввода:
        // Flutter сличает детей по месту и типу, а не по смыслу, — появление
        // ряда сдвигало поле на позицию вниз, и оно пересоздавалось. Живьём это
        // стоило связи с системным текстовым вводом, а через неё на macOS идёт
        // `Backspace`: печатать можно, а стереть нечем. Та же ошибка, что с
        // обводкой фокуса (`spec/dialog-focus.md`), и лечится так же.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_suggestions(theme, state), _input(theme, state, enabled, style)],
        );
      },
    );
  }

  /// Из чего выбирать — одной строкой над вводом.
  ///
  /// Без окна нарочно: список из трёх имён окна не стоит, а список из трёхсот
  /// бесполезен и в окне. Не влезло — многоточие, подставленное видно жирным.
  Widget _suggestions(FcTheme theme, CommandLineState state) {
    final colors = theme.colors;
    final metrics = theme.metrics;
    final base = TextStyle(fontFamily: theme.fonts.fixed, fontSize: metrics.fontSize, color: colors.secondaryText);
    if (!state.isCompleting || state.suggestions.length < 2) {
      return const SizedBox.shrink();
    }

    return Container(
      color: colors.panelBackground,
      padding: EdgeInsets.symmetric(horizontal: metrics.labelPadding + metrics.cellPadding),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < state.suggestions.length; i++) ...[
                    if (i > 0) TextSpan(text: '   ', style: base),
                    TextSpan(
                      text: state.suggestions[i].insertion,
                      style:
                          i == state.suggestionIndex
                              ? base.copyWith(color: colors.cursorText, fontWeight: FontWeight.bold)
                              : base,
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: metrics.columnGap),
          // Что делать дальше — словами: из ряда имён это не очевидно, а
          // догадываться человек не должен.
          Text('Tab next · Enter accept · Esc cancel', maxLines: 1, style: base.copyWith(color: colors.pathText)),
        ],
      ),
    );
  }

  Widget _input(FcTheme theme, CommandLineState state, bool enabled, TextStyle style) {
    final colors = theme.colors;
    final metrics = theme.metrics;

    return Container(
      height: metrics.inputHeight,
      color: colors.panelBackground,
      padding: EdgeInsets.symmetric(horizontal: metrics.panelLeftPadding),
      child: Row(
        children: [
          // Приглашение — это каталог, в котором всё и произойдёт. Оно же
          // объясняет, почему строка приглушена: путь в архиве или на
          // сервере видно так же, как обычный.
          Flexible(
            child: Text(
              '${state.prompt}\$',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: enabled ? colors.pathText : colors.secondaryText),
            ),
          ),
          SizedBox(width: metrics.columnGap),
          Expanded(
            flex: 3,
            child:
                enabled
                    ? TextField(
                      // Ключ — чтобы поле оставалось тем же самым, что бы ни
                      // происходило вокруг: пересозданное, оно теряет связь с
                      // клавиатурой.
                      key: const ValueKey('command-line-input'),
                      controller: state.text,
                      focusNode: _node,
                      style: style,
                      cursorColor: colors.rowText,
                      cursorWidth: metrics.strokeWidth * 2,
                      decoration: const InputDecoration.collapsed(hintText: null),
                    )
                    : Text('Shell does not work here', maxLines: 1, style: style.copyWith(color: colors.secondaryText)),
          ),
        ],
      ),
    );
  }
}
