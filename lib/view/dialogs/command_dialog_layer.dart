import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_controller.dart';
import '../../state/commands/app_command.dart';
import '../../state/commands/key_combination.dart';
import '../theme/app_theme.dart';

/// Окна запущенных команд.
///
/// Ядро рисует рамку, заголовок и затемнение, а содержимое берёт у самой
/// команды — [AppCommand.getDialog]. Так все окна выглядят одинаково, но
/// команда полностью распоряжается тем, что внутри, и меняет это по ходу
/// работы: ввод, ход выполнения, вопрос, ошибка.
class CommandDialogLayer extends StatelessWidget {
  const CommandDialogLayer({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app.commands,
      builder: (context, _) {
        final dialogs = app.commands.openDialogs;
        if (dialogs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            for (final command in dialogs)
              if (command.getDialog(context) case final content?)
                _CommandDialogFrame(key: ValueKey(command.runId), command: command, child: content),
          ],
        );
      },
    );
  }
}

/// Рамка окна команды: затемнение, заголовок, содержимое и общие клавиши.
///
/// Enter и Esc обрабатывает ядро, одинаково для всех команд: пока команда не
/// исполняется, Enter выполняет её с уже заданными параметрами, а Esc
/// закрывает окно. Команде остаётся только следить, чтобы параметры были
/// заданы к этому моменту.
class _CommandDialogFrame extends StatefulWidget {
  const _CommandDialogFrame({super.key, required this.command, required this.child});

  final AppCommand command;
  final Widget child;

  @override
  State<_CommandDialogFrame> createState() => _CommandDialogFrameState();
}

class _CommandDialogFrameState extends State<_CommandDialogFrame> {
  /// Фокус самого окна.
  ///
  /// Нужен для окон, в которых нечего фокусировать: без него клавиши уходили бы
  /// в панели, а окно оставалось бы глухим к Enter и Esc. Если окно ставит
  /// фокус само (поле ввода), рама его не забирает, а события всё равно
  /// поднимаются сюда от поля.
  final FocusNode _node = FocusNode(debugLabel: 'command dialog');

  AppCommand get command => widget.command;

  @override
  void initState() {
    super.initState();
    if (!command.dialogTakesFocus) {
      _node.requestFocus();
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final combination = KeyCombination.fromEvent(event);
    if (combination == null || command.isRunning) {
      return KeyEventResult.ignored;
    }

    if (combination == const KeyCombination('Enter')) {
      command.submit();
      return KeyEventResult.handled;
    }
    if (combination == const KeyCombination('Esc')) {
      command.dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;

    final metrics = theme.metrics;
    final radius = BorderRadius.circular(metrics.dialogRadius);

    return Stack(
      children: [
        // Затемнение: пока окно открыто, работать с панелями нельзя.
        Positioned.fill(child: ModalBarrier(dismissible: false, color: colors.dialogBarrier)),
        Center(
          child: FocusScope(
            autofocus: true,
            // Обработчик стоит на самой области окна: если внутри есть поле
            // ввода, событие поднимется сюда от него, а если фокусировать
            // нечего — фокус берёт само окно.
            onKeyEvent: _handleKey,
            child: Focus(
              focusNode: _node,
              child: Container(
                constraints: BoxConstraints(minWidth: metrics.dialogMinWidth, maxWidth: metrics.dialogMaxWidth),
                decoration: BoxDecoration(
                  color: colors.dialogBackground,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      offset: Offset(0, metrics.dialogShadowOffset),
                      blurRadius: metrics.dialogShadowBlur,
                    ),
                  ],
                ),
                // Скруглённые углы обрезают полосу заголовка: в референсе
                // она для этого закрыта маской.
                clipBehavior: Clip.antiAlias,
                // Ширина — по содержимому: главным образом по ряду кнопок,
                // которые в референсе стоят одной строкой и не растягиваются.
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: double.infinity,
                        height: metrics.dialogTitleHeight,
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.symmetric(horizontal: metrics.dialogTitlePadding),
                        decoration: BoxDecoration(
                          color: colors.dialogTitleBackground,
                          // Полоса заголовка отбрасывает тень на содержимое —
                          // тот же фильтр, что у кнопок.
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow,
                              offset: Offset(0, metrics.buttonShadowOffset),
                              blurRadius: metrics.buttonShadowBlur,
                            ),
                          ],
                        ),
                        child: Text(command.dialogTitle, style: theme.dialogTitleStyle),
                      ),
                      widget.child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
