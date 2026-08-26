import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  }

  @override
  void dispose() {
    view.removeListener(_syncFocus);
    _node.dispose();
    super.dispose();
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
      listenable: Listenable.merge([state, view, state.panel]),
      builder: (context, _) {
        final enabled = state.enabled;
        final style = TextStyle(
          fontFamily: theme.fonts.fixed,
          fontSize: metrics.fontSize,
          color: enabled ? colors.rowText : colors.secondaryText,
        );

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
                        ? Shortcuts(
                          // `Tab` строка проглатывает: место занято под будущее
                          // дополнение путей, а обычный обход увёл бы фокус
                          // неизвестно куда — из полосы, которая одна.
                          shortcuts: const {
                            SingleActivator(LogicalKeyboardKey.tab): DoNothingAndStopPropagationIntent(),
                          },
                          child: TextField(
                            controller: state.text,
                            focusNode: _node,
                            style: style,
                            cursorColor: colors.rowText,
                            cursorWidth: metrics.strokeWidth * 2,
                            decoration: const InputDecoration.collapsed(hintText: null),
                          ),
                        )
                        : Text(
                          'Оболочка здесь не работает',
                          maxLines: 1,
                          style: style.copyWith(color: colors.secondaryText),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}
