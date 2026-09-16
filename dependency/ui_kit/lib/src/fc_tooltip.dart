import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Подсказка: наведи мышь — и обрезанное договорится целиком.
///
/// Элемент дизайн-системы, а не серый прямоугольник Material
/// (`docs/spec/tooltips.md`, §4). Оформление — то же, что у всплывающего
/// сообщения: всплывшая поверхность в приложении одна, и заводить ей вторую
/// палитру незачем.
///
/// **Свой, а не материальный с перекрашенной темой.** Тема сняла бы серый
/// прямоугольник, но оставила бы главную беду: материальный `Tooltip` кладёт в
/// дерево свои распознаватели жестов (долгое нажатие), а они уходят в общую
/// арену и спорят за то же нажатие, что строка списка и источник
/// перетаскивания. Этот не заводит **ни одного** жеста: наведение — обычный
/// `MouseRegion`, а за указателем он наблюдает глобальным маршрутом, который
/// события видит, но не отнимает.
///
/// Пустое сообщение — виджет отдаёт [child] как есть, и подсказки нет вовсе.
/// Это договор, а не поблажка: так [FcTrimmedText] ставит подсказку
/// безусловно и не плодит ветку у каждого вызывающего.
class FcTooltip extends StatefulWidget {
  const FcTooltip({super.key, required this.message, required this.child});

  /// Что договорить. Приходит готовым: имя файла и путь — это данные, а
  /// подпись переводит тот, кто её знает (`docs/spec/localization.md`).
  final String message;

  final Widget child;

  /// Сколько держать мышь, прежде чем подсказка всплывёт.
  ///
  /// Числом в одном месте на всё приложение — столько же (600 мс) стояло
  /// руками в четырёх местах из шести, а в двух его забыли вовсе. В набор
  /// размеров задержка не переехала нарочно: тот зеркалится в макет
  /// линейками, а задержку линейкой не измерить (`docs/spec/tooltips.md`, §4).
  static const Duration delay = Duration(milliseconds: 600);

  /// Ключ всплывшей подсказки — по нему её находят проверки.
  ///
  /// Иначе искать нечего: подсказка живёт в накладке и отличается от
  /// договариваемого текста только тем, что показана дважды.
  static const Key viewKey = Key('fc-tooltip');

  /// Есть ли подсказка выше по дереву.
  ///
  /// Спрашивает [FcTrimmedText]: договаривать дважды одно и то же не нужно, а
  /// вложенные подсказки всплывали бы обе — наведение приходит всем, кто под
  /// курсором. Право старшего: плашка пути говорит о всей плашке (и о крошках,
  /// которые роняют звенья), а текст внутри неё — только о себе.
  static bool above(BuildContext context) => context.getInheritedWidgetOfExactType<_FcTooltipScope>() != null;

  @override
  State<FcTooltip> createState() => _FcTooltipState();
}

/// Метка «здесь уже договаривают» для тех, кто внутри.
class _FcTooltipScope extends InheritedWidget {
  const _FcTooltipScope({required super.child});

  @override
  bool updateShouldNotify(_FcTooltipScope oldWidget) => false;
}

class _FcTooltipState extends State<FcTooltip> {
  Timer? _timer;
  OverlayEntry? _shown;

  @override
  void initState() {
    super.initState();
    _pointers.watch();
  }

  @override
  void didUpdateWidget(FcTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message != oldWidget.message) {
      // Текст сменился под курсором — показываем новый, а не прежний.
      widget.message.isEmpty ? _hide() : _refresh();
    }
  }

  @override
  void deactivate() {
    // Строка уехала из ленивого списка — подсказке не за что держаться.
    _hide();
    super.deactivate();
  }

  @override
  void dispose() {
    _hide();
    _pointers.unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) {
      return widget.child;
    }

    // Строение неизменно: внутри всегда один и тот же `MouseRegion`, а сама
    // подсказка живёт в накладке, в дерево панели не входящей. Поэтому её
    // появление не трогает ни прокрутку, ни слой пометки, ни источник
    // перетаскивания (`docs/spec/mouse-marking.md`, §6).
    return _FcTooltipScope(
      child: MouseRegion(onEnter: (_) => _wait(), onHover: (_) => _wait(), onExit: (_) => _hide(), child: widget.child),
    );
  }

  /// Перерисовать показанную подсказку новым текстом.
  ///
  /// **Следующим кадром, а не сейчас.** Текст подсказки может смениться
  /// из-под раскладки — так бывает у показа, который живёт внутри
  /// `LayoutBuilder`, — и пометить запись наложения в этот миг нельзя: каркас
  /// уже строит дерево и законно ругается «setState during build». Кадр
  /// задержки на подсказке не виден, а падение в журнале видно хорошо.
  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Запись могла уйти, пока кадр шёл: подсказку спрятали, строка уехала.
      final shown = _shown;
      if (shown != null && shown.mounted) {
        shown.markNeedsBuild();
      }
    });
  }

  /// Завести отсчёт — если он уже идёт, не перезаводить.
  ///
  /// Иначе подсказка не всплыла бы никогда, пока мышь едет вдоль длинного
  /// имени: каждое движение отодвигало бы срок. Наведение зовёт то же, что и
  /// вход: после нажатия отсчёт снят, и вернуть его может только движение —
  /// нового входа не будет, курсор и так на месте.
  void _wait() {
    if (_timer != null || _shown != null || _pointers.pressed) {
      return;
    }
    _timer = Timer(FcTooltip.delay, _show);
  }

  void _show() {
    _timer = null;
    if (!mounted || _pointers.pressed) {
      return;
    }

    final box = context.findRenderObject();
    // Накладка — корневая: весь экран лежит внутри маршрута навигатора, и
    // подсказка обязана всплыть выше всего, включая сообщения.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final area = overlay?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || area is! RenderBox) {
      return;
    }

    final anchor = box.localToGlobal(Offset.zero, ancestor: area) & box.size;
    final entry = OverlayEntry(builder: (context) => _FcTooltipView(message: widget.message, anchor: anchor));
    overlay!.insert(entry);
    _shown = entry;
    _pointers.showing(this);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _shown?.remove();
    _shown = null;
    _pointers.hidden(this);
  }
}

/// Сама подсказка: поверхность, текст и место, где она встанет.
class _FcTooltipView extends StatelessWidget {
  const _FcTooltipView({required this.message, required this.anchor});

  final String message;

  /// Прямоугольник виджета, из которого подсказка выросла, — в осях накладки.
  final Rect anchor;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;

    return IgnorePointer(
      // Подсказка ничего не спрашивает и ничем не управляет. Без этого она,
      // всплыв под курсором, перекрыла бы виджет, из которого выросла: тот
      // получил бы «мышь ушла», подсказка погасла бы, курсор вернулся — и
      // вышло бы мигание в такт кадрам.
      child: CustomSingleChildLayout(
        delegate: _FcTooltipLayout(anchor: anchor, gap: metrics.dialogLineGap, share: metrics.dialogMaxScreenFactor),
        child: Container(
          key: FcTooltip.viewKey,
          padding: EdgeInsets.symmetric(horizontal: metrics.toastHorizontalPadding, vertical: metrics.toastPadding),
          decoration: BoxDecoration(
            // Оформление всплывающего сообщения: обе поверхности всплывают
            // поверх окна, и вторая палитра им ни к чему. Рамки нет — у
            // сообщения она означает отказ, и второго значения ей не давать.
            color: colors.dialogBackground,
            borderRadius: BorderRadius.circular(metrics.dialogRadius),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                offset: Offset(0, metrics.buttonShadowOffset),
                blurRadius: metrics.buttonShadowBlur,
              ),
            ],
          ),
          // Стиль назван целиком, а не дополнен окружением: накладка — своя
          // ветка отрисовки, ни `Material`, ни наших стилей над ней нет. `Text`
          // со стилем-наследником подмешал бы отладочный запасной стиль — и
          // подсказка выходила бы жирной, с жёлтым двойным подчёркиванием.
          child: DefaultTextStyle(style: theme.uiStyle.copyWith(color: colors.dialogText), child: Text(message)),
        ),
      ),
    );
  }
}

/// Куда встать: под виджетом, а если снизу тесно — над ним.
///
/// **Под виджетом, а не под курсором**: подсказка, прыгающая за мышью по
/// списку, — ровно то, от чего отказались (`docs/spec/tooltips.md`, §4). Заодно
/// она стоит на месте, пока мышь ходит внутри имени.
class _FcTooltipLayout extends SingleChildLayoutDelegate {
  const _FcTooltipLayout({required this.anchor, required this.gap, required this.share});

  final Rect anchor;
  final double gap;

  /// Доля окна, шире которой подсказке не быть: путь в двести знаков одной
  /// строкой во всю ширину читается хуже обрезанного имени, поэтому текст
  /// переносится.
  final double share;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().copyWith(maxWidth: constraints.maxWidth * share);

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: anchor.center,
    // `positionDependentBox` сам перекидывает подсказку наверх, когда снизу
    // нет места, и держит её в пределах накладки — то есть окна приложения.
    preferBelow: true,
    verticalOffset: anchor.height / 2 + gap,
  );

  @override
  bool shouldRelayout(_FcTooltipLayout old) => anchor != old.anchor || gap != old.gap || share != old.share;
}

/// Наблюдение за указателем: одна подсказка на приложение и замок на время
/// нажатия.
///
/// **Замок закрывает оба жеста панели сразу** — и пометку протягиванием, и
/// перетаскивание файлов: оба начинаются с нажатия. Спросить у службы
/// перетаскивания, тянут ли сейчас, всё равно нельзя — она живёт в модуле,
/// которого набор виджетов не видит по слоям (`test/app/layering_test.dart`).
///
/// Без замка было бы плохо не в теории: наведение приходит и с зажатой
/// кнопкой, а при автопрокрутке пометки строки едут под неподвижным курсором —
/// подсказки всплывали бы очередью посреди жеста.
class _FcTooltipPointers {
  final Set<int> _down = {};
  _FcTooltipState? _current;
  int _watchers = 0;

  bool get pressed => _down.isNotEmpty;

  /// Маршрут ставится с первой подсказкой и снимается с последней: пока
  /// показывать некому — слушать нечего.
  void watch() {
    if (_watchers++ == 0) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  void unwatch() {
    if (--_watchers == 0) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      _down.clear();
    }
  }

  void showing(_FcTooltipState state) {
    // Вторая подсказка гасит первую: их всегда ровно одна.
    if (!identical(_current, state)) {
      _current?._hide();
    }
    _current = state;
  }

  void hidden(_FcTooltipState state) {
    if (identical(_current, state)) {
      _current = null;
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _down.add(event.pointer);
      _current?._hide();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      // Отпускание доходит и тогда, когда мышь забрала система: раннер
      // досылает его сам (`docs/spec/drag-and-drop.md`, §10).
      _down.remove(event.pointer);
    } else if (event is PointerSignalEvent) {
      // Колесо увозит строку из-под подсказки — держаться ей не за что.
      _current?._hide();
    }
  }
}

final _FcTooltipPointers _pointers = _FcTooltipPointers();
