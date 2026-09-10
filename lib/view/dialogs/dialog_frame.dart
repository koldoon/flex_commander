import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
        // Тем же полем, что и содержимое: заголовок и подписи под ним стоят на
        // одной вертикали, и левый край окна читается прямым.
        padding: EdgeInsets.symmetric(horizontal: metrics.dialogHorizontalPadding),
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
        // Заголовок приходит значением — от того, кто окно открыл. Переводит
        // его тот, кто показывает: иначе окно, открытое до смены языка,
        // осталось бы с прежним заголовком (`docs/spec/localization.md`, §3).
        //
        // Строго одна строка: в заголовке стоит имя файла, а оно бывает какой
        // угодно длины. Перенос рвал бы полосу — высота у неё ровно в строку.
        child: _UnmeasuredTitle(
          child: Text(
            context.strings.tr(title),
            style: theme.dialogTitleStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// Ширина окна над названной областью: область минус поле с каждой стороны.
  ///
  /// **Число, а не «по содержимому».** Содержимое окна меняется на глазах —
  /// в ходе работы бегут имена файлов, список отбирается по набранному, —
  /// и окно, облегающее его, дёргалось бы шириной на каждом шаге
  /// (`docs/spec/dialog-placement.md`, §3).
  ///
  /// Не меньше `dialogMinWidth`: на узком экране важнее прочитать окно, чем
  /// попасть точно над панелью, — то же правило, что и у раскладки.
  ///
  /// У окна над всем приложением ширины отсюда нет вовсе (`infinity`): оно
  /// либо назначает её себе само (`ownWidth`), либо облегает содержимое в
  /// пределах темы, и области, чьи границы стоило бы беречь, у него нет.
  double _areaWidth(BuildContext context, FcMetrics metrics) {
    if (widget.area.width >= 1) {
      return double.infinity;
    }
    final width = MediaQuery.sizeOf(context).width * widget.area.width;
    return math.max(metrics.dialogMinWidth, width - metrics.dialogAreaInset * 2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;

    final metrics = theme.metrics;
    final radius = BorderRadius.circular(metrics.dialogRadius);
    final areaWidth = _areaWidth(context, metrics);

    return Stack(
      children: [
        // Затемнение: пока окно открыто, работать с панелями нельзя.
        Positioned.fill(child: ModalBarrier(dismissible: false, color: colors.dialogBarrier)),
        CustomSingleChildLayout(
          delegate: _OverArea(
            widget.area,
            metrics.dialogMinWidth,
            // Поле между границей области и окном: без него окно над панелью
            // ложится стык в стык с её рамкой
            // (`docs/spec/dialog-placement.md`).
            metrics.dialogAreaInset,
            _shift,
            metrics.dialogDragKeepVisible,
            // Отступ сверху один на все окна и берётся из темы: окно, стоящее
            // по середине высоты, дёргалось бы при каждой смене содержимого —
            // палитра растёт по мере набора, окно выбора вида — вслед за
            // настройками того вида, на котором курсор.
            metrics.dialogTopInset,
          ),
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
                // Пределы — для окна над всем приложением: оно облегает
                // содержимое, и держат его `minWidth`/`maxWidth`. Нужен
                // определённый размер — команда задаёт его сама в том, что
                // вернула из `dialogSpec`, и тогда же снимает верхний предел
                // (`ownWidth`): он в точках, а такая ширина в долях экрана, и
                // на широком экране предел обрезал бы её тем сильнее, чем
                // экран шире.
                //
                // У окна над панелью ширина своя и точная — [DialogWidth].
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: metrics.dialogMinWidth,
                    maxWidth: widget.ownWidth ? double.infinity : metrics.dialogMaxWidth,
                  ),
                  child: DialogWidth(
                    width: areaWidth,
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

/// Ширина окна: назначенная областью или по содержимому.
///
/// Окно над **панелью** получает точное число — ширину своей области без полей
/// (`docs/spec/dialog-placement.md`, §3). Не «облегает содержимое»: содержимое
/// меняется на глазах — бегут имена файлов, отбирается список, — и окно по нему
/// дрожало бы шириной на каждом шаге.
///
/// Окно над **всем приложением** ширину берёт по содержимому, как и раньше:
/// области, от которой её считать, у него нет.
///
/// Оно же — само окно в дереве виджетов: рама вокруг занимает всю область
/// вместе с затемнением, а окно — то, что внутри. По нему окно и находят в
/// проверках.
class DialogWidth extends StatelessWidget {
  const DialogWidth({super.key, required this.width, required this.child});

  /// Ширина окна; `infinity` — по содержимому.
  final double width;

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      width.isFinite ? SizedBox(width: width, child: child) : IntrinsicWidth(child: child);
}

/// Ставит окно над заданной частью экрана.
///
/// `Align` для этого не годится: он раскладывает по **свободному** месту, и
/// широкое окно уезжает от задуманного тем сильнее, чем оно шире.
///
/// Ширина ограничивается не самой областью, а границами, посчитанными от неё:
/// окно не касается границ своей панели, а не поместившись — заходит на
/// соседнюю, но не дальше её середины (`docs/spec/dialog-placement.md`, §3).
/// Ниже [minWidth] не жмёт: на узком экране важнее прочитать окно, чем попасть
/// точно над панелью.
class _OverArea extends SingleChildLayoutDelegate {
  const _OverArea(this.area, this.minWidth, this.inset, this.shift, this.keepVisible, this.topInset);

  final DialogArea area;
  final double minWidth;

  /// Поле между границей области и окном.
  final double inset;

  /// Сколько сверху до окна — одно число на все окна.
  ///
  /// Середина по высоте не годится ни одному: содержимое меняется прямо на
  /// глазах — палитра растёт по мере набора, окно выбора вида показывает
  /// настройки выбранного, — а окно, растущее вокруг своей середины, дёргает
  /// обе границы разом. По горизонтали середина остаётся: там ничего не
  /// растёт.
  final double topInset;

  /// Куда окно отодвинули руками.
  final Offset shift;

  /// Сколько окна остаётся видно, как далеко его ни утащили.
  final double keepVisible;

  /// В каких границах окну дозволено лежать (`docs/spec/dialog-placement.md`,
  /// §3).
  ///
  /// Внутри своей области — с полем от границ; наружу — только в ту сторону,
  /// где места больше, и не дальше её середины. Область во всё приложение
  /// границ не имеет вовсе: беречь там нечего, соседа у неё нет.
  (double, double) _bounds(double width) {
    final start = width * area.start;
    final end = width * area.end;
    final outsideLeft = start;
    final outsideRight = width - end;
    if (outsideLeft <= 0 && outsideRight <= 0) {
      return (0, width);
    }
    // Расти — в ту сторону, где просторнее: у левой панели сосед справа, у
    // правой слева. Ближний край при этом остаётся на поле от своей границы.
    return outsideRight >= outsideLeft
        ? (start + inset, end + outsideRight / 2)
        : (start - outsideLeft / 2, end - inset);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final (low, high) = _bounds(constraints.maxWidth);
    final allowed = math.max(minWidth, high - low);
    return constraints.loosen().copyWith(maxWidth: math.min(constraints.maxWidth, allowed));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final (low, high) = _bounds(size.width);
    // Одно правило на оба случая: середина области, прижатая к границам.
    // Узкое окно так и стоит посередине панели, широкое упирается ближним
    // краем в поле и заходит на соседнюю.
    final right = math.max(low, high - childSize.width);
    var x = (size.width * area.center - childSize.width / 2).clamp(math.min(low, right), right).toDouble();

    // За край окна приложения не выпускаем: на узком окне важнее видеть окно
    // целиком, чем держать его точно над панелью.
    final free = math.max(0.0, size.width - childSize.width);
    x = x.clamp(0.0, free).toDouble();

    final freeHeight = math.max(0.0, size.height - childSize.height);
    // Высокое окно поднимается ровно настолько, чтобы поместиться: обещание
    // «не дёргаться» кончается там, где начинается «не влезло».
    final y = math.min(topInset, freeHeight);

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
      (y + shift.dy).clamp(0.0, freeHeight),
    );
  }

  @override
  bool shouldRelayout(_OverArea oldDelegate) =>
      oldDelegate.area != area ||
      oldDelegate.minWidth != minWidth ||
      oldDelegate.inset != inset ||
      oldDelegate.shift != shift ||
      oldDelegate.keepVisible != keepVisible ||
      oldDelegate.topInset != topInset;
}

/// Заголовок, который **не** решает, какой окну быть ширины.
///
/// Ширину окна задаёт его содержимое или область, над которой оно встало
/// (`docs/spec/dialog-placement.md`, §3), — заголовку в этом счёте места нет.
/// Иначе длинное имя файла растягивало бы окно до предела темы, а упёршись в
/// него, переносилось бы на вторую строку и рвало полосу заголовка: высота у
/// неё ровно в строку.
///
/// Из той же породы, что `_Shrinkable` в форме окна, только строже: там
/// нулевой становится наименьшая ширина, здесь — обе. Разница в том, что поле
/// ввода окно вырасти под себя вправе, а заголовок — нет.
class _UnmeasuredTitle extends SingleChildRenderObjectWidget {
  const _UnmeasuredTitle({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderUnmeasuredTitle();
}

class _RenderUnmeasuredTitle extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}
