import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'fc_theme.dart';

/// Мигание нарисованного курсора.
///
/// Курсор рисуют сами те места, под которыми **нет системного поля ввода**:
/// быстрый поиск в панели и командная строка в режиме `mc`. Клавиши им отдаёт
/// приложение, а не система, и `TextField` там не стоит — но мигать курсор
/// обязан всё равно: неподвижная палочка читается как рисунок, а не как место,
/// куда попадёт следующее нажатие.
///
/// [builder] зовётся с тем, виден ли курсор **сейчас**, — рисовать можно что
/// угодно: полоску, блок, знак внутри строки текста. Прятать его лучше цветом,
/// а не отсутствием: исчезнувший виджет менял бы ширину строки дважды в
/// секунду.
///
/// [resetOn] — то, от чего мигание начинается заново: пока печатают, курсор
/// должен быть виден, а не пропадать на полсекунды посреди набора. Обычно сюда
/// передают сам набранный текст.
class FcCursorBlink extends StatefulWidget {
  const FcCursorBlink({super.key, required this.builder, this.resetOn});

  final Widget Function(BuildContext context, bool visible) builder;

  final Object? resetOn;

  /// Полупериод: полсекунды виден, полсекунды нет.
  ///
  /// Ровно как у полей самого Flutter (`_kCursorBlinkHalfPeriod`): наш курсор
  /// и системный стоят в одной и той же строке — в режиме `mc` рисованный, без
  /// него настоящий, — и мигать вразнобой им нельзя.
  static const Duration halfPeriod = Duration(milliseconds: 500);

  /// Выключает мигание: курсор виден всё время.
  ///
  /// То же самое и ровно затем же, что `EditableText.debugDeterministicCursor`
  /// у Flutter. Бесконечное мигание — это кадр каждые полсекунды, а
  /// `pumpAndSettle` ждёт, пока кадры кончатся, и не дождался бы никогда.
  ///
  /// **Это свойство прогона, а не показа.** Выключает его `testApp`, один раз
  /// и за всех; помнить о нём отдельному тесту не нужно, а показу — незачем
  /// становиться хуже ради тестов.
  static bool debugDeterministicCursor = false;

  @override
  State<FcCursorBlink> createState() => _FcCursorBlinkState();
}

class _FcCursorBlinkState extends State<FcCursorBlink> {
  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(FcCursorBlink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetOn != oldWidget.resetOn) {
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Начинает отсчёт заново, с видимого курсора.
  void _start() {
    _timer?.cancel();
    _visible = true;
    if (FcCursorBlink.debugDeterministicCursor) {
      return;
    }
    _timer = Timer.periodic(FcCursorBlink.halfPeriod, (_) {
      setState(() => _visible = !_visible);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _visible);
}

/// Курсор ввода там, где системного поля нет: полоска стандартного вида.
///
/// Одна на всех, кто рисует курсор сам, — чтобы «место, куда попадёт нажатие»
/// выглядело одинаково во всём приложении: та же толщина
/// ([FcMetrics.caretWidth]), те же полукруглые торцы ([FcMetrics.caretRadius]),
/// та же высота и то же мигание.
///
/// **Высота считается по стилю текста, а не по кеглю.** Курсор настоящего поля
/// ростом со строку (`preferredLineHeight` у `EditableText`), а она выше кегля
/// на межстрочную прибавку шрифта. Взяв кегль, полоска выходит заметно ниже
/// соседних полей — видно сразу, стоит поставить их рядом. Поэтому сюда
/// передаётся [style] — тот же, которым набранное и нарисовано, — а высоту
/// курсор меряет тем же счётом, что и Flutter.
///
/// Прячется цветом, а не отсутствием: исчезнув, полоска двигала бы соседний
/// текст дважды в секунду.
class FcCaret extends StatelessWidget {
  const FcCaret({super.key, required this.style, this.color, this.resetOn});

  /// Стиль строки, рядом с которой стоит курсор: по нему считается высота.
  final TextStyle style;

  /// Цвет; пусто — цвет текста в поле.
  final Color? color;

  /// От чего мигание начинается заново — обычно сам набранный текст.
  final Object? resetOn;

  /// Высота строки этого стиля — ровно то, чем меряет себя курсор настоящего
  /// поля: `TextPainter.preferredLineHeight`.
  static double lineHeightOf(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.preferredLineHeight;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return FcCursorBlink(
      resetOn: resetOn,
      builder:
          (context, visible) => SizedBox(
            width: metrics.caretWidth,
            height: lineHeightOf(context, style),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: visible ? (color ?? theme.colors.inputText) : const Color(0x00000000),
                borderRadius: BorderRadius.circular(metrics.caretRadius),
              ),
            ),
          ),
    );
  }
}
