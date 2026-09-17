import 'dart:async';
import 'dart:math' as math;

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Пометка правой кнопкой: жест целиком.
///
/// Спецификация — `docs/spec/mouse-marking.md`.
///
/// Отдельным местом, а не в состоянии вида: жест один и тот же в списке и в
/// сетке значков, а два одинаковых жеста однажды разойдутся — и разойдутся
/// молча, мелочью вроде «ход назад снимает лишнее».
///
/// От вида требуется ровно три вещи: где строка под указателем, где строка
/// **ближайшая** к нему (когда указатель ушёл за край) и какую область считать
/// списком. Как эти строки разложены — рядами, столбцами, плитками — жесту
/// безразлично: отрезок он считает по порядку списка.
class MarkDrag {
  MarkDrag({
    required this.panel,
    required this.indexAt,
    required this.indexNear,
    required this.bounds,
    required this.scroll,
    required this.activate,
    this.rowsBetween,
  });

  /// Насколько далеко за краем список едет с наибольшей скоростью.
  static const double autoScrollReach = 120;

  /// Наибольший шаг автопрокрутки за такт.
  static const double autoScrollStep = 24;

  static const Duration autoScrollTick = Duration(milliseconds: 16);

  final Session panel;

  /// Строка точно под указателем; null — мимо строк (заголовки, пустое место).
  final int? Function(Offset local) indexAt;

  /// Строка, к которой тянут: за краями списка — крайняя видимая, а не
  /// последняя в каталоге. Иначе указатель, ушедший за нижний край, помечал бы
  /// каталог до конца одним махом.
  final int Function(Offset local) indexNear;

  /// Верх и низ области списка в местных координатах: по ним видно, что
  /// указатель ушёл за край.
  final (double top, double bottom) Function() bounds;

  /// Способом узнать, а не значением: список пересоздаёт свой контроллер, и
  /// жест, запомнивший прежний, молча перестаёт ехать у края.
  final ScrollController Function() scroll;

  /// Сделать панель активной: жест начался в ней.
  final void Function() activate;

  /// Какие строки лежат **между** двумя номерами; пусто — все подряд.
  ///
  /// Нужно тому виду, где соседние на экране строки не соседи в списке: в
  /// столбцах между двумя строками одного каталога лежит чужое раскрытое
  /// поддерево, и протяжка пометила бы его **невидимо** — а оттуда оно уехало
  /// бы в цели `F5` (`docs/spec/panel-view-columns.md`, §9).
  final List<int> Function(int low, int high)? rowsBetween;

  /// Строка, с которой жест начался; -1 — жеста нет.
  int _anchor = -1;

  /// Докуда дотянули в прошлый раз: строки за отрезком нужно вернуть в прежнее
  /// состояние, а знать, какие именно, можно только помня прошлый конец.
  int _to = -1;

  /// Помечаем или снимаем — решает первая строка жеста.
  bool _adds = true;

  /// Пометка, какой она была до жеста: по ней восстанавливаются строки,
  /// выпавшие из отрезка при ходе назад.
  Set<String> _before = const {};

  Offset _pointer = Offset.zero;
  Timer? _timer;

  /// Идёт ли жест прямо сейчас.
  bool get active => _anchor >= 0;

  /// Жест — это правая кнопка, чем бы её ни нажали.
  ///
  /// Устройство не проверяется: протянуть с зажатой правой на трекпаде и так
  /// невозможно (правый щелчок там — двухпальцевый тап), а переключить пометку
  /// одной строки им можно, и запрещать это незачем.
  static bool isMarking(int buttons) => buttons == kSecondaryMouseButton;

  /// Начало жеста: запоминаем строку, снимок пометки и направление.
  ///
  /// Направление задаёт первая строка: начали с непомеченной — весь отрезок
  /// помечается, начали с помеченной — снимается. Отдельной ветки «просто
  /// щелчок» нет: он и есть отрезок длиной в одну строку.
  void down(PointerDownEvent event) {
    if (!isMarking(event.buttons)) {
      return;
    }
    // Начаться жест может только на строке: над заголовками колонок правая
    // кнопка по-прежнему открывает меню видимости.
    final index = indexAt(event.localPosition);
    if (index == null) {
      return;
    }

    activate();

    _anchor = index;
    _to = index;
    _before = panel.markedPaths;
    _adds = !panel.isMarked(panel.entries[index]);
    _pointer = event.localPosition;
    segment(index);
  }

  void move(PointerMoveEvent event) {
    if (!active || !isMarking(event.buttons)) {
      return;
    }
    _pointer = event.localPosition;
    segment(indexNear(event.localPosition));
    _autoScroll(event.localPosition);
  }

  void up(PointerEvent event) {
    _anchor = -1;
    _before = const {};
    _timer?.cancel();
    _timer = null;
  }

  /// Забыть жест: вид разбирают, и таймер его не переживёт.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Приводит к нужному виду отрезок от начальной строки до [to], а всё, что
  /// из отрезка выпало, возвращает в состояние до жеста.
  ///
  /// Отрезок, а не след: ход назад снимает то, что жест сам же и пометил.
  void segment(int to) {
    if (!active) {
      return;
    }
    final entries = panel.entries;
    final from = _anchor;

    final low = math.min(from, math.min(to, _to));
    final high = math.max(from, math.max(to, _to));
    final segmentLow = math.min(from, to);
    final segmentHigh = math.max(from, to);

    // Пометка меняется одной просьбой на весь отрезок: до ядра она едет
    // путями, и слать по сообщению на строку значило бы гнать сотню сообщений
    // за один взмах мыши.
    final marked = <String>{...panel.markedPaths};
    final touched = rowsBetween?.call(low, high) ?? [for (var i = low; i <= high && i < entries.length; i++) i];
    for (final i in touched) {
      if (i < 0 || i >= entries.length) {
        continue;
      }
      final entry = entries[i];
      // «..» не помечается никогда — это правило самой пометки, и жесту
      // достаточно его не обходить.
      if (entry.isParent) {
        continue;
      }
      final wanted = i >= segmentLow && i <= segmentHigh ? _adds : _before.contains(entry.path);
      if (wanted) {
        marked.add(entry.path);
      } else {
        marked.remove(entry.path);
      }
    }
    panel.setMarks(marked);

    _to = to;
    // Курсор идёт за жестом: иначе после пометки полутора экранов он остаётся
    // там, где его забыли, и следующая клавиша делает не то, что человек видит.
    panel.setCursorIndex(to);
  }

  /// У краёв список едет сам — иначе жестом нельзя пометить больше экрана.
  ///
  /// Скорость растёт с тем, насколько далеко указатель ушёл за край: одна
  /// скорость на все случаи либо мучительна на длинном списке, либо
  /// проскакивает нужное место. Шаг делается по таймеру, а не по движениям
  /// мыши: остановленную за краем руку список обязан слушаться дальше.
  void _autoScroll(Offset local) {
    if (_overEdge(local.dy) == 0) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(autoScrollTick, (_) => _stepped());
  }

  /// Насколько указатель ушёл за край области: вверх — отрицательное, вниз —
  /// положительное, внутри — ноль.
  double _overEdge(double dy) {
    final (top, bottom) = bounds();
    if (dy < top) {
      return dy - top;
    }
    return dy > bottom ? dy - bottom : 0.0;
  }

  void _stepped() {
    final scroll = this.scroll();
    if (!active || !scroll.hasClients) {
      return;
    }
    final over = _overEdge(_pointer.dy);
    if (over == 0) {
      return;
    }

    final speed = (over.abs() / autoScrollReach).clamp(0.0, 1.0) * autoScrollStep;
    final position = scroll.position;
    final target = (position.pixels + (over < 0 ? -speed : speed)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }
    scroll.jumpTo(target);
    segment(indexNear(_pointer));
  }
}
