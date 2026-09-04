import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Рамка модального окна: затемнение, заголовок, содержимое и общие клавиши.
///
/// Enter и Esc рама только **передаёт** дальше — [onSubmit] и [onDismiss], — а
/// что они значат, решает содержимое. У команды это обычно «выполнить с
/// заданными параметрами» и «закрыть окно», но у длительной команды Esc посреди
/// работы означает просьбу её прервать, а во время вопроса обе клавиши отвечают
/// на него (см. `FcAsyncRun`). Разбирать эти случаи здесь значило бы
/// рассказывать раме о состояниях того, что она обрамляет.
///
/// Рама не знает и о том, чьё это окно: кроме команд, ею пользуется вопрос о
/// пароле, который задаёт не команда, а провайдер из глубины.
class DialogFrame extends StatefulWidget {
  const DialogFrame({
    super.key,
    required this.onSubmit,
    required this.onDismiss,
    required this.child,
    this.title,
    this.takesFocus = false,
    this.area = DialogArea.window,
    this.ownWidth = false,
  });

  /// Заголовок; null — полосы нет, и окно **не двигается**: ручка была ею.
  final String? title;

  /// Enter и Esc соответственно.
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  /// Содержимое ставит фокус само (поле ввода) — тогда рама его не забирает.
  final bool takesFocus;

  /// Часть окна приложения, над которой встаёт окно. Обычно всё окно, но окно
  /// про названную панель встаёт над ней самой.
  final DialogArea area;

  /// Окно назначает ширину само — верхний предел рамы к нему не применяется
  /// (`DialogSpec.ownWidth`).
  final bool ownWidth;

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

  /// Куда окно отодвинули от места, назначенного командой.
  ///
  /// Живёт здесь, а не в слое окон: слой создаёт раму с ключом по описанию
  /// окна, поэтому это состояние живёт ровно столько же, сколько само окно, и
  /// умирает вместе с ним. Отдельного хранилища и ключей к нему не нужно.
  Offset _shift = Offset.zero;

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

  /// Полоса заголовка — она же ручка, за которую окно отодвигают.
  ///
  /// Только она: за содержимое окно не тянут — там поля, кнопки и списки, и
  /// движение по ним значит своё. В macOS ровно так же. **Отсюда и следствие
  /// у окна без заголовка: двигать его нечем**, и это не недоделка — второй
  /// ручки у окна нет и заводить её незачем.
  ///
  /// Порога у протяжки нет: окно едет с первой же точки. Порог нужен там, где
  /// с протяжкой спорит щелчок (заголовки колонок — `drag_slop.dart`), а здесь
  /// щелчок по заголовку не значит ничего.
  Widget _titleBar(FcTheme theme, FcColors colors, FcMetrics metrics, String title) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Отсчёт от нажатия, а не от того места, где протяжка признана протяжкой:
      // иначе окно отставало бы от указателя и так и ехало бы со сдвигом до
      // самого конца.
      dragStartBehavior: DragStartBehavior.down,
      onPanUpdate: (details) => setState(() => _shift += details.delta),
      child: Container(
        width: double.infinity,
        height: metrics.dialogTitleHeight,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: metrics.dialogTitlePadding),
        decoration: BoxDecoration(
          color: colors.dialogTitleBackground,
          // Полоса заголовка отбрасывает тень на содержимое — тот же фильтр,
          // что у кнопок.
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              offset: Offset(0, metrics.buttonShadowOffset),
              blurRadius: metrics.buttonShadowBlur,
            ),
          ],
        ),
        child: Text(title, style: theme.dialogTitleStyle),
      ),
    );
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
        CustomSingleChildLayout(
          delegate: _OverArea(widget.area, metrics.dialogMinWidth, _shift, metrics.dialogDragKeepVisible),
          child: FocusScope(
            autofocus: true,
            // Обработчик стоит на самой области окна: если внутри есть поле
            // ввода, событие поднимется сюда от него, а если фокусировать
            // нечего — фокус берёт само окно.
            //
            // Кнопка и флажок разбирают свои клавиши раньше: Flutter отдаёт
            // нажатие сперва узлу в фокусе, потом вверх по предкам. Поэтому
            // `Enter` на кнопке нажимает её, а не подтверждает окно, — а `Esc`
            // не берёт себе никто, и он доходит сюда откуда угодно.
            onKeyEvent: _handleKey,
            // Обход замкнут внутри окна: за окном панели, и `Tab` там значит
            // «сменить панель». Порядок — по дереву: как выложено, так и
            // обходится, отдельного списка держать не приходится.
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: Focus(
                focusNode: _node,
                // Узел рамы нужен, чтобы окно слышало клавиши, когда внутри
                // фокусировать нечего. Останавливаться на нём `Tab`у незачем.
                skipTraversal: true,
                // Ширину рамка не назначает: окно облегает содержимое в пределах
                // `minWidth`/`maxWidth`. Нужен определённый размер — команда
                // задаёт его сама в том, что вернула из `dialogSpec`, и тогда
                // же снимает верхний предел (`ownWidth`): он в точках, а такая
                // ширина в долях экрана, и на широком экране предел обрезал бы
                // её тем сильнее, чем экран шире.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: metrics.dialogMinWidth,
                    maxWidth: widget.ownWidth ? double.infinity : metrics.dialogMaxWidth,
                  ),
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
                          if (widget.title case final title?) _titleBar(theme, colors, metrics, title),
                          widget.child,
                        ],
                      ),
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

/// Ставит окно над заданной частью экрана.
///
/// `Align` для этого не годится: он раскладывает по **свободному** месту, и
/// широкое окно уезжает от задуманного тем сильнее, чем оно шире. Ширина при
/// этом ограничивается самой областью — окно шире панели над ней не
/// поместится, как ни выравнивай, — но не ниже [minWidth]: на узком экране
/// важнее прочитать окно, чем попасть точно над панелью.
class _OverArea extends SingleChildLayoutDelegate {
  const _OverArea(this.area, this.minWidth, this.shift, this.keepVisible);

  final DialogArea area;
  final double minWidth;

  /// Куда окно отодвинули руками.
  final Offset shift;

  /// Сколько окна остаётся видно, как далеко его ни утащили.
  final double keepVisible;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final allowed = math.max(minWidth, constraints.maxWidth * area.width);
    return constraints.loosen().copyWith(maxWidth: math.min(constraints.maxWidth, allowed));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // За край не выпускаем: на узком окне важнее видеть окно целиком, чем
    // держать его точно над панелью.
    final free = math.max(0.0, size.width - childSize.width);
    final x = (size.width * area.center - childSize.width / 2).clamp(0.0, free).toDouble();
    final y = (size.height - childSize.height) / 2;

    // Отодвинутое руками окно уехать совсем не может: тянут за полосу
    // заголовка, и спрятанное под край не вернуть ничем.
    //
    // Считается это на **каждой** раскладке, а не при отпускании: окно
    // приложения меняет размер, и уведённое к правому краю обязано остаться
    // достижимым после того, как приложение сузили.
    final visible = math.min(keepVisible, childSize.width);
    return Offset(
      (x + shift.dx).clamp(visible - childSize.width, size.width - visible),
      // По вертикали полоса заголовка видна целиком: за неё и тянут.
      (y + shift.dy).clamp(0.0, math.max(0.0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_OverArea oldDelegate) =>
      oldDelegate.area != area ||
      oldDelegate.minWidth != minWidth ||
      oldDelegate.shift != shift ||
      oldDelegate.keepVisible != keepVisible;
}
