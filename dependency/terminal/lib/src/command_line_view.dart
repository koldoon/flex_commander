import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';

import 'command_line_state.dart';
import 'terminal_commands.dart';

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
    // Строку могли собрать **заново уже с вводом за ней**: под полноэкранным её
    // нет вовсе, и когда оно уходит — это новый виджет с новым узлом фокуса.
    // Слушатель тут не поможет, менять больше нечего: область и была `bottom`.
    //
    // Без этого курсора не оказывалось нигде. Состояние говорило «ввод у
    // строки», поле было пустым и не мигало, а `Cmd-T` — привязка панельная —
    // до команды не доходила вовсе: короткий сигнал и ничего. Выбраться можно
    // было только `Esc`.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFocus());
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
    if (!mounted) {
      return;
    }
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
    final state = widget.state;

    return ListenableBuilder(
      // Поле тоже: подсказка дополнения уходит от любой правки строки, а о
      // правке знает только контроллер текста.
      listenable: Listenable.merge([state, view, state.panel, state.text]),
      builder: (context, _) {
        final enabled = state.enabled;
        final style = theme.fixedStyle.copyWith(color: enabled ? colors.rowText : colors.secondaryText);

        // Ряд подсказок стоит **всегда**, даже когда он пуст.
        //
        // `if` здесь менял бы строение дерева, а вместе с ним и поле ввода:
        // Flutter сличает детей по месту и типу, а не по смыслу, — появление
        // ряда сдвигало поле на позицию вниз, и оно пересоздавалось. Живьём это
        // стоило связи с системным текстовым вводом, а через неё на macOS идёт
        // `Backspace`: печатать можно, а стереть нечем. Та же ошибка, что с
        // обводкой фокуса (`spec/dialog-focus.md`), и лечится так же.
        //
        // Воздуха вокруг себя строка не отмеряет вовсе: зазоры до панелей и до
        // ряда кнопок стоят снаружи, и ставит их шелл — тем же расстоянием, что
        // и между всеми прочими областями (`spec/layout-gaps.md`).
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
    final base = theme.fixedStyle.copyWith(color: colors.secondaryText);
    if (!state.isCompleting || state.suggestions.length < 2) {
      return const SizedBox.shrink();
    }

    return Container(
      // Та же высота, что у полосы ввода, и текст в ней так же по центру: это
      // две полосы одной строки, и рядом друг с другом они обязаны стоять
      // одинаково. Без этого кандидаты липли к рамке панели, а поле — нет:
      // воздух ему давала высота, а им не давал никто.
      height: metrics.inputHeight,
      alignment: Alignment.centerLeft,
      color: colors.windowBackground,
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

  /// Набранное в режиме `mc`: текст и нарисованный курсор.
  ///
  /// Курсор здесь рисуется сам, потому что поля ввода под ним нет вовсе: в
  /// режиме `mc` клавиши разбирают привязки, а не система. Мигает он при этом
  /// так же, как настоящий, и с тем же полупериодом: человек судит о том, куда
  /// уходит набор, по курсору, а неподвижный курсор об этом не говорит ничего.
  ///
  /// [takesKeys] — достанутся ли буквы **строке**. Полоса под панелью
  /// (быстрый поиск) забирает их себе, и курсор в этот момент обязан быть
  /// там, а не здесь: двух курсоров на экране не бывает. Место он при этом
  /// не отпускает — прячется цветом, иначе набранное дёргалось бы вбок каждый
  /// раз, когда открывают и закрывают поиск.
  Widget _typed(FcTheme theme, CommandLineState state, TextStyle style, {required bool takesKeys}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FcCursorBlink(
        // Набор сбрасывает мигание: пока печатают, курсор виден.
        resetOn: state.text.text,
        builder:
            (context, visible) => Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: state.text.text, style: style),
                  // Курсор блоком, как в терминале, — но прячется он цветом, а
                  // не отсутствием: пропав из строки, блок дважды в секунду
                  // менял бы её длину.
                  TextSpan(
                    text: '\u2588',
                    style: style.copyWith(
                      color: visible && takesKeys ? theme.colors.cursorBackground : const Color(0x00000000),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      ),
    );
  }

  /// Доля строки, которую ввод оставляет себе, каким бы длинным ни был путь.
  ///
  /// Треть — чтобы набранное было видно целиком хотя бы на короткой команде.
  /// Путь при этом режется многоточием: он всё-таки подпись к работе, а
  /// работают в поле.
  static const double _inputShare = 1 / 3;

  Widget _input(FcTheme theme, CommandLineState state, bool enabled, TextStyle style) {
    final colors = theme.colors;
    final metrics = theme.metrics;

    return Container(
      height: metrics.inputHeight,
      // Фон окна, а не панели: `panelBackground` — это белый пятипроцентный
      // поверх окна, и кладёт его рамка панели. Строка рамки не имеет и стоит
      // под панелями, а не внутри: взяв панельный цвет, она притворялась бы
      // куском панели и вылезала бы полутоном на общем фоне.
      color: colors.windowBackground,
      padding: EdgeInsets.symmetric(horizontal: metrics.panelLeftPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Приглашение занимает столько, сколько ему нужно, — но не за счёт
          // ввода: [_inputShare] строки остаётся ему всегда.
          //
          // Делили долями `1:3`, и путь чуть длиннее четверти строки резался
          // многоточием, хотя справа было пусто: доли не спрашивают, есть ли
          // кому занять место. Обычный домашний путь под четверть не влезает —
          // так это и вылезло.
          final reserved = constraints.maxWidth * _inputShare + metrics.columnGap;
          final promptLimit = (constraints.maxWidth - reserved).clamp(0.0, constraints.maxWidth);

          return Row(
            children: [
              // Приглашение — это каталог, в котором всё и произойдёт. Оно же
              // объясняет, почему строка приглушена: путь в архиве или на
              // сервере видно так же, как обычный.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: promptLimit),
                child: Text(
                  '${state.prompt}\$',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: enabled ? colors.pathText : colors.secondaryText),
                ),
              ),
              SizedBox(width: metrics.columnGap),
              Expanded(
                child:
                    !enabled
                        ? Text(
                          'Shell does not work here',
                          maxLines: 1,
                          style: style.copyWith(color: colors.secondaryText),
                        )
                        // В режиме `mc` поля ввода нет вовсе: ввод у панели, и все
                        // клавиши строки разбираются привязками. Курсор строка
                        // рисует сама — иначе человеку неоткуда узнать, что печать
                        // уходит сюда.
                        : state.typingGoesToLine && view.activeArea != ViewportPosition.bottom
                        // Клавиши строке достаются не всегда: полоса под
                        // панелью может забрать их себе. Условие то же, что у
                        // самой команды печати, — иначе показ и разбор
                        // разойдутся.
                        ? _typed(theme, state, style, takesKeys: !statusTakesKeys(state.app))
                        : TextField(
                          // Ключ — чтобы поле оставалось тем же самым, что бы ни
                          // происходило вокруг: пересозданное, оно теряет связь с
                          // клавиатурой.
                          key: const ValueKey('command-line-input'),
                          controller: state.text,
                          focusNode: _node,
                          style: style,
                          cursorColor: colors.rowText,
                          cursorWidth: metrics.caretWidth,
                          cursorRadius: Radius.circular(metrics.caretRadius),
                          decoration: const InputDecoration.collapsed(hintText: null),
                        ),
              ),
            ],
          );
        },
      ),
    );
  }
}
