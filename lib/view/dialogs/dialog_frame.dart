import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:fc_api/fc_api.dart';
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
    this.id,
    this.resizable = false,
  });

  /// Имя окна: под ним оно помнит о себе всё, что переживает перезапуск
  /// (`DialogSpec.id`). null — помнить негде, и размер живёт, пока окно
  /// открыто.
  final String? id;

  /// Окно тянется за края и углы (`docs/spec/dialog-resize.md`).
  final bool resizable;

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

  /// Размер, заданный человеком; null — считает рама, как считала всегда.
  Size? _size;

  /// Содержимое окна — чтобы спросить у него, ниже чего оно не ужимается.
  final GlobalKey _content = GlobalKey(debugLabel: 'dialog content');

  /// Само окно — чтобы знать, от какого размера тянут.
  ///
  /// Не рама: рама занимает всю область вместе с затемнением, и первое же
  /// движение от её размера швырнуло бы окно к пределу.
  final GlobalKey _window = GlobalKey(debugLabel: 'dialog window');

  bool _restored = false;

  @override
  void initState() {
    super.initState();
    if (!widget.takesFocus) {
      _node.requestFocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Запомненное поднимается один раз, при первом показе: дальше окно живёт
    // своим размером, и перечитывать настройки на каждую перестройку значило
    // бы затирать то, что человек тянет прямо сейчас.
    if (_restored || !widget.resizable) {
      return;
    }
    _restored = true;
    if (widget.id case final id?) {
      final saved = AppScope.read(context).dialogState(id);
      if (saved != null && saved.hasWidth && saved.hasHeight) {
        _size = Size(saved.width, saved.height);
      }
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

  // --- растяжение -----------------------------------------------------------

  /// Ниже чего окно не ужимается.
  ///
  /// **Числа темы, а не требование содержимого** — и это не упрощение, а
  /// поправка по замеру. Спрашивать содержимое интринсиками мы пробовали:
  /// `Table` справки объявляет своей наименьшей шириной 876 точек, живя при
  /// этом в 800, — потому что «наименьшая» у таблицы это её естественные
  /// столбцы, а не предел, ниже которого нельзя. Окно от такого предела
  /// прыгало на первом же движении, а высота переставала меняться вовсе
  /// (`docs/spec/dialog-resize.md`, §12).
  ///
  /// Содержимому это и не нужно: оно **обязано** уметь ужиматься, потому что
  /// ширину ему назначает рама (`dialog-placement.md`, §4а).
  Size _minSize(FcMetrics metrics) => Size(metrics.dialogMinWidth, metrics.dialogMinHeight);

  /// Больше рабочей области окна приложения окно не растягивается.
  ///
  /// По высоте область считается от того отступа, на котором окно стоит: ниже
  /// края экрана ему всё равно не показаться.
  Size _maxSize(BuildContext context, FcMetrics metrics) {
    final screen = MediaQuery.sizeOf(context);
    return Size(screen.width, math.max(metrics.dialogMinHeight, screen.height - metrics.dialogTopInset));
  }

  /// Размер, поджатый под нынешнее окно приложения.
  ///
  /// Считается на каждой раскладке, а не один раз при отпускании: окно
  /// приложения меняет размер, и окно команды обязано в него влезать. В
  /// настройках при этом остаётся то, что задал человек: сузили приложение и
  /// расширили обратно — вернулся и размер окна (`docs/spec/dialog-resize.md`,
  /// §7).
  Size? _fitted(BuildContext context, FcMetrics metrics) {
    final size = _size;
    if (size == null) {
      return null;
    }
    final min = _minSize(metrics);
    final max = _maxSize(context, metrics);
    return Size(
      size.width.clamp(math.min(min.width, max.width), math.max(min.width, max.width)),
      size.height.clamp(math.min(min.height, max.height), math.max(min.height, max.height)),
    );
  }

  /// Тянут за край: меняем размер, а края, двигающие начало окна, — ещё и
  /// смещение.
  void _resize(_Edge edge, Offset delta, Size current, FcMetrics metrics) {
    final min = _minSize(metrics);
    final max = _maxSize(context, metrics);

    var width = current.width;
    var height = current.height;
    var shift = _shift;

    // **По горизонтали окно стоит серединой области, по вертикали — от верха**
    // (`_OverArea`), и поправки к смещению у них разные. Считаются они от
    // *применённого* изменения, а не от того, на сколько потянули: у предела
    // окно перестаёт расти, и продолжать двигать его было бы неправдой.
    if (edge.left || edge.right) {
      final wanted = edge.right ? width + delta.dx : width - delta.dx;
      final applied = wanted.clamp(min.width, max.width) - width;
      // Растёт окно в обе стороны от середины, поэтому противоположный край
      // остаётся на месте, когда середина уезжает на половину прибавки.
      shift += Offset(edge.right ? applied / 2 : -applied / 2, 0);
      width += applied;
    }

    if (edge.top || edge.bottom) {
      final wanted = edge.bottom ? height + delta.dy : height - delta.dy;
      final applied = wanted.clamp(min.height, max.height) - height;
      // Верх окна прибит к своему отступу: вниз оно растёт само, а вверх — на
      // всю прибавку целиком.
      if (edge.top) {
        shift += Offset(0, -applied);
      }
      height += applied;
    }

    if (width == current.width && height == current.height) {
      return;
    }
    setState(() {
      _size = Size(width, height);
      _shift = shift;
    });
  }

  /// Отпустили — запоминаем. Если окну негде помнить, размер живёт до
  /// закрытия, и это всё равно лучше, чем ничего.
  void _rememberSize() {
    final id = widget.id;
    final size = _size;
    if (id == null || size == null) {
      return;
    }
    AppScope.read(context).rememberDialogState(id, DialogState(width: size.width, height: size.height));
  }

  /// Двойной щелчок по краю возвращает размер по умолчанию.
  ///
  /// Без сброса неудачно растянутое окно чинится только правкой файла
  /// настроек руками, а это не ответ (`docs/spec/dialog-resize.md`, §9).
  void _resetSize() {
    setState(() => _size = null);
    if (widget.id case final id?) {
      AppScope.read(context).rememberDialogState(id, DialogState());
    }
  }

  /// Окно вместе с полосами, за которые его тянут.
  ///
  /// Полосы лежат **внутри** окна, по его краю, и с полосой заголовка не
  /// пересекаются: тянут за край рамы, двигают за заголовок. Поэтому спора
  /// между двумя жестами нет и модификатор не нужен — так же устроены окна
  /// системы (`docs/spec/dialog-resize.md`, §5).
  Widget _withHandles(FcMetrics metrics, Size? fitted, Widget window) {
    if (!widget.resizable) {
      return window;
    }

    final edge = metrics.dialogResizeEdge;
    // Угол — самая полезная ручка и самая труднодоступная: шесть точек на
    // шесть попробуй поймай. Вдвое от края по каждой оси, и стороны на эту
    // длину укорачиваются — угол лежит поверх и выигрывает нажатие.
    final corner = edge * 2;
    // Размер нужен, чтобы считать от него: пока окно не тянули, он тот, что
    // назначила рама, и берётся у самого окна при первом же движении.
    Size current() => fitted ?? _windowSize() ?? Size.zero;

    Widget handle(_Edge at, {double? left, double? top, double? right, double? bottom, double? width, double? height}) {
      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: at.cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Отсчёт от нажатия, как и у перетаскивания: иначе окно отставало
            // бы от указателя на порог распознавания.
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => _beginResize(metrics),
            onPanUpdate: (details) => _resize(at, details.delta, _size ?? current(), metrics),
            onPanEnd: (_) => _rememberSize(),
            onDoubleTap: _resetSize,
          ),
        ),
      );
    }

    return Stack(
      children: [
        window,
        handle(const _Edge(left: true), left: 0, top: corner, bottom: corner, width: edge),
        handle(const _Edge(right: true), right: 0, top: corner, bottom: corner, width: edge),
        handle(const _Edge(top: true), left: corner, right: corner, top: 0, height: edge),
        handle(const _Edge(bottom: true), left: corner, right: corner, bottom: 0, height: edge),
        handle(const _Edge(left: true, top: true), left: 0, top: 0, width: corner, height: corner),
        handle(const _Edge(right: true, top: true), right: 0, top: 0, width: corner, height: corner),
        handle(const _Edge(left: true, bottom: true), left: 0, bottom: 0, width: corner, height: corner),
        handle(const _Edge(right: true, bottom: true), right: 0, bottom: 0, width: corner, height: corner),
      ],
    );
  }

  /// Первое движение: окну назначается тот размер, какой у него сейчас.
  ///
  /// До этого размера у окна нет вовсе — его считает рама, — и тянуть «от
  /// ничего» нельзя: первое же движение должно продолжать то, что человек
  /// видит, а не прыгать к пределу.
  void _beginResize(FcMetrics metrics) {
    if (_size != null) {
      return;
    }
    final size = _windowSize();
    if (size == null) {
      return;
    }
    final min = _minSize(metrics);
    setState(() => _size = Size(math.max(size.width, min.width), math.max(size.height, min.height)));
  }

  /// Нынешний размер самого окна; null — окна ещё нет на экране.
  Size? _windowSize() {
    final box = _window.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : null;
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
    final fitted = _fitted(context, metrics);

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
                    maxWidth: widget.ownWidth || fitted != null ? double.infinity : metrics.dialogMaxWidth,
                  ),
                  child: _withHandles(
                    metrics,
                    fitted,
                    DialogWidth(
                      width: fitted?.width ?? areaWidth,
                      child: Container(
                        key: _window,
                        // Высота задана — значит задана: без этого окно
                        // осталось бы по содержимому, и нижний край тянулся бы
                        // вхолостую.
                        height: fitted?.height,
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
                          // Заданная высота заполняется целиком: содержимое
                          // тянется вместе с окном, а не жмётся к заголовку.
                          mainAxisSize: fitted == null ? MainAxisSize.min : MainAxisSize.max,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.title case final title?) _titleBar(theme, colors, metrics, title),
                            // Содержимое, которому не хватило высоты, прокручивается
                            // — а не вылезает за раму молчащим переполнением.
                            //
                            // `Flexible`, а не `Expanded`: невысокому окну лишняя
                            // высота не нужна, оно по-прежнему облегает содержимое.
                            // Прокрутка появляется только там, где иначе было бы
                            // переполнение: окно правки атрибутов у файла с
                            // десятком расширенных именно таково.
                            //
                            // Полоса заголовка при этом остаётся на месте: за неё
                            // окно двигают, и уезжать ей нельзя.
                            Flexible(
                              child: SingleChildScrollView(child: KeyedSubtree(key: _content, child: widget.child)),
                            ),
                          ],
                        ),
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

/// Край окна, за который тянут.
///
/// Восемь: четыре стороны и четыре угла. Угол — это просто два края разом, и
/// отдельного случая ему не нужно.
class _Edge {
  const _Edge({this.left = false, this.right = false, this.top = false, this.bottom = false});

  final bool left;
  final bool right;
  final bool top;
  final bool bottom;

  /// Тянется ли этот край по обеим осям — то есть угол ли это.
  bool get isCorner => (left || right) && (top || bottom);

  /// Курсор над этим краем.
  ///
  /// **У macOS диагональных курсоров нет вовсе.** В открытом API `NSCursor`
  /// их не существует: системные окна рисует оконный сервер своими,
  /// недоступными. Flutter это и не скрывает — у `resizeUpLeftDownRight` в
  /// списке платформ macOS не значится, — но подставляет вместо него обычную
  /// стрелку, и угол выглядит так, будто за него не тянут
  /// (`docs/spec/dialog-resize.md`, §5).
  ///
  /// Поэтому там, где диагонали нет, угол показывает курсор той оси, которую
  /// у окна меняют чаще, — горизонтальной. Полуправда лучше неправды: стрелка
  /// говорит «тут ничего нет», а этот курсор — «тут тянут».
  MouseCursor get cursor {
    if (isCorner) {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        return SystemMouseCursors.resizeLeftRight;
      }
      return (left && top) || (right && bottom)
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft;
    }
    return left || right ? SystemMouseCursors.resizeLeftRight : SystemMouseCursors.resizeUpDown;
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
