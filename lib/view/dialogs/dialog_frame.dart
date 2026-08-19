import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fc_api/fc_api.dart';

/// Рамка модального окна: затемнение, заголовок, содержимое и общие клавиши.
///
/// Enter и Esc рама только **передаёт** дальше — [onSubmit] и [onDismiss], — а
/// что они значат, решает содержимое. У команды это обычно «выполнить с
/// заданными параметрами» и «закрыть окно», но у длительной команды Esc посреди
/// работы означает просьбу её прервать, а во время вопроса обе клавиши отвечают
/// на него (см. `AsyncCommandBase`). Разбирать эти случаи здесь значило бы
/// рассказывать раме о состояниях того, что она обрамляет.
///
/// Рама не знает и о том, чьё это окно: кроме команд, ею пользуется вопрос о
/// пароле, который задаёт не команда, а провайдер из глубины.
class DialogFrame extends StatefulWidget {
  const DialogFrame({
    super.key,
    required this.title,
    required this.onSubmit,
    required this.onDismiss,
    required this.child,
    this.takesFocus = false,
  });

  final String title;

  /// Enter и Esc соответственно.
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  /// Содержимое ставит фокус само (поле ввода) — тогда рама его не забирает.
  final bool takesFocus;

  final Widget child;

  @override
  State<DialogFrame> createState() => _DialogFrameState();
}

class _DialogFrameState extends State<DialogFrame> {
  /// Фокус самого окна.
  ///
  /// Нужен для окон, в которых нечего фокусировать: без него клавиши уходили бы
  /// в панели, а окно оставалось бы глухим к Enter и Esc. Если окно ставит
  /// фокус само (поле ввода), рама его не забирает, а события всё равно
  /// поднимаются сюда от поля.
  final FocusNode _node = FocusNode(debugLabel: 'dialog frame');

  @override
  void initState() {
    super.initState();
    if (!widget.takesFocus) {
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
    if (combination == null) {
      return KeyEventResult.ignored;
    }

    if (combination == const KeyCombination('Enter')) {
      widget.onSubmit();
      return KeyEventResult.handled;
    }
    if (combination == const KeyCombination('Esc')) {
      widget.onDismiss();
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
              // Ширину рамка не назначает: окно облегает содержимое в пределах
              // `minWidth`/`maxWidth`. Нужен определённый размер — команда
              // задаёт его сама в том, что вернула из `getDialog`.
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: metrics.dialogMinWidth, maxWidth: metrics.dialogMaxWidth),
                child: IntrinsicWidth(
                  child: Container(
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
                          child: Text(widget.title, style: theme.dialogTitleStyle),
                        ),
                        widget.child,
                      ],
                    ),
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
