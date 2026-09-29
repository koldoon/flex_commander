import 'dart:math' as math;
import 'dart:ui';

import '../draw/diagram_layout.dart';
import '../draw/diagram_text.dart';
import 'sequence_model.dart';

/// Размеры раскладки. Числами, а не ролями темы: это устройство одной картинки.
class SequenceMetrics {
  const SequenceMetrics({
    this.margin = 12,
    this.columnGap = 24,
    this.headerPadding = 12,
    this.headerGap = 20,
    this.minColumn = 64,
    this.messageGap = 22,
    this.labelGap = 6,
    this.selfLoop = 44,
    this.activation = 8,
    this.blockInset = 8,
    this.blockGap = 12,
    this.notePadding = 8,
    this.noteGap = 10,
  });

  /// Поле вокруг всей диаграммы.
  final double margin;

  /// Наименьший зазор между шапками участников.
  final double columnGap;

  /// Отступ подписи внутри шапки.
  final double headerPadding;

  /// От низа шапок до первого шага.
  final double headerGap;

  /// Наименьшая ширина столбца.
  final double minColumn;

  /// После стрелки до следующего шага.
  final double messageGap;

  /// Между подписью и стрелкой.
  final double labelGap;

  /// Ширина петли сообщения самому себе.
  final double selfLoop;

  /// Ширина полосы активности.
  final double activation;

  /// Насколько рамка блока шире своего содержимого.
  final double blockInset;

  /// После закрытой рамки.
  final double blockGap;

  /// Отступ текста внутри заметки.
  final double notePadding;

  /// Вокруг заметки.
  final double noteGap;
}

/// Разложить диаграмму последовательности.
///
/// Чистый расчёт: на входе модель и замер текста, на выходе фигуры и размер.
/// Ни холста, ни виджетов здесь нет (`docs/spec/mermaid.md`, §4).
DiagramLayout layoutSequence(
  SequenceDiagram diagram,
  DiagramTextMeasure measure, {
  SequenceMetrics metrics = const SequenceMetrics(),
}) {
  if (diagram.participants.isEmpty) {
    return DiagramLayout.empty;
  }

  return _Layout(diagram, measure, metrics).run();
}

class _Layout {
  _Layout(this.diagram, this.measure, this.metrics);

  final SequenceDiagram diagram;
  final DiagramTextMeasure measure;
  final SequenceMetrics metrics;

  /// Шапки участников: замеренная подпись и ширина столбца.
  final List<DiagramTextRun> _headers = [];
  final List<double> _widths = [];

  /// Центры столбцов.
  final List<double> _centres = [];

  final Map<String, int> _column = {};

  /// Фигуры по слоям: линии жизни, полосы активности, содержимое, рамки.
  final List<DiagramShape> _lifelines = [];
  final List<DiagramShape> _bars = [];
  final List<DiagramShape> _content = [];
  final List<DiagramShape> _frames = [];

  /// Открытые полосы активности: участник → стек начал.
  final Map<String, List<double>> _active = {};

  /// Счётчик `autonumber`.
  int _number = 0;

  double _y = 0;
  double _headerBottom = 0;

  /// Насколько диаграмма вылезла вправо за последний столбец.
  double _overhang = 0;

  DiagramLayout run() {
    _measureHeaders();
    _placeColumns();
    _widenForLabels();

    _y = metrics.margin + _headerHeight() + metrics.headerGap;
    _headerBottom = metrics.margin + _headerHeight();

    _walk(diagram.steps, 0);
    _closeDanglingActivations();

    final bottom = _y + metrics.margin;
    _drawHeaders();
    _drawLifelines(bottom - metrics.margin);

    final right = math.max(_centres.last + _widths.last / 2, _overhang) + metrics.margin;

    // Рамки **до** содержимого: иначе их линии легли бы поверх надписей, и
    // подложка под надписью не спасала бы.
    return DiagramLayout(size: Size(right, bottom), shapes: [..._lifelines, ..._bars, ..._frames, ..._content]);
  }

  double _headerHeight() => _headers.map((run) => run.size.height).reduce(math.max) + metrics.headerPadding * 2;

  void _measureHeaders() {
    for (var i = 0; i < diagram.participants.length; i++) {
      final participant = diagram.participants[i];
      final run = measure.run(participant.label, DiagramTextRole.participant);
      _headers.add(run);
      _widths.add(math.max(run.size.width + metrics.headerPadding * 2, metrics.minColumn));
      _column[participant.id] = i;
    }
  }

  void _placeColumns() {
    var x = metrics.margin;
    for (var i = 0; i < _widths.length; i++) {
      _centres.add(x + _widths[i] / 2);
      x += _widths[i] + metrics.columnGap;
    }
  }

  /// Раздвинуть столбцы под подписи сообщений.
  ///
  /// Повторяется, пока что-то двигалось, но не дольше числа сообщений: на
  /// кривых данных цикл обязан кончиться (`docs/spec/mermaid.md`, §6).
  void _widenForLabels() {
    final messages = _allMessages(diagram.steps).toList();

    for (var pass = 0; pass <= messages.length; pass++) {
      var moved = false;

      for (final message in messages) {
        final from = _column[message.from]!;
        final to = _column[message.to]!;
        final width = _labelWidth(message);

        if (from == to) {
          // Петле нужен запас справа: её ширина плюс подпись.
          final need = metrics.selfLoop + width + metrics.labelGap;
          if (from + 1 < _centres.length) {
            final have = _centres[from + 1] - _centres[from];
            if (have < need) {
              _shift(from + 1, need - have);
              moved = true;
            }
          } else {
            _overhang = math.max(_overhang, _centres[from] + need);
          }
          continue;
        }

        final left = math.min(from, to);
        final right = math.max(from, to);
        final have = _centres[right] - _centres[left];
        final need = width + metrics.labelGap * 2;
        if (have < need) {
          _shift(right, need - have);
          moved = true;
        }
      }

      if (!moved) {
        return;
      }
    }
  }

  void _shift(int from, double by) {
    for (var i = from; i < _centres.length; i++) {
      _centres[i] += by;
    }
  }

  double _labelWidth(SequenceMessage message) =>
      message.label.isEmpty ? 0 : measure.run(message.label.join('\n'), DiagramTextRole.message).size.width;

  Iterable<SequenceMessage> _allMessages(List<SequenceStep> steps) sync* {
    for (final step in steps) {
      if (step is SequenceMessage) {
        yield step;
      } else if (step is SequenceBlock) {
        for (final section in step.sections) {
          yield* _allMessages(section.steps);
        }
      }
    }
  }

  void _walk(List<SequenceStep> steps, int depth) {
    for (final step in steps) {
      switch (step) {
        case SequenceMessage():
          _message(step);
        case SequenceNote():
          _note(step);
        case SequenceActivation():
          _activation(step);
        case SequenceBlock():
          _block(step, depth);
      }
    }
  }

  void _message(SequenceMessage message) {
    final from = _centres[_column[message.from]!];
    final to = _centres[_column[message.to]!];

    if (message.activates) {
      _active.putIfAbsent(message.to, () => []).add(_y);
    }

    final text = _numbered(message);
    final run = text.isEmpty ? null : measure.run(text, DiagramTextRole.message);

    if (message.isSelf) {
      final top = _y;
      final height = metrics.messageGap;
      if (run != null) {
        _content.add(
          DiagramLabel(run: run, at: Offset(from + metrics.selfLoop + metrics.labelGap, top), backdrop: true),
        );
        _y += run.size.height + metrics.labelGap;
      }
      final loopTop = _y;
      _content.add(
        DiagramPath(
          points: [
            Offset(from, loopTop),
            Offset(from + metrics.selfLoop, loopTop),
            Offset(from + metrics.selfLoop, loopTop + height),
            Offset(from, loopTop + height),
          ],
          head: _head(message.arrow.head),
          dashed: message.arrow.dotted,
        ),
      );
      _y = loopTop + height + metrics.messageGap;
    } else {
      if (run != null) {
        final centre = (from + to) / 2;
        _content.add(DiagramLabel(run: run, at: Offset(centre - run.size.width / 2, _y), backdrop: true));
        _y += run.size.height + metrics.labelGap;
      }
      _content.add(
        DiagramPath(
          points: [Offset(from, _y), Offset(to, _y)],
          head: _head(message.arrow.head),
          dashed: message.arrow.dotted,
        ),
      );
      _y += metrics.messageGap;
    }

    if (message.deactivates) {
      _closeActivation(message.to);
    }
  }

  /// Подпись с номером, если просили нумеровать.
  String _numbered(SequenceMessage message) {
    final text = message.label.join('\n');
    if (!diagram.autonumber) {
      return text;
    }
    _number++;

    return text.isEmpty ? '$_number' : '$_number. $text';
  }

  DiagramHead _head(ArrowHead head) => switch (head) {
    ArrowHead.none => DiagramHead.none,
    ArrowHead.arrow => DiagramHead.arrow,
    ArrowHead.cross => DiagramHead.cross,
    ArrowHead.open => DiagramHead.open,
  };

  void _note(SequenceNote note) {
    final run = measure.run(note.label.join('\n'), DiagramTextRole.note);
    final width = run.size.width + metrics.notePadding * 2;
    final height = run.size.height + metrics.notePadding * 2;

    final anchor = _centres[_column[note.of.first]!];
    final left = switch (note.placement) {
      NotePlacement.leftOf => anchor - width - metrics.columnGap / 2,
      NotePlacement.rightOf => anchor + metrics.columnGap / 2,
      NotePlacement.over =>
        note.of.length > 1 ? (anchor + _centres[_column[note.of.last]!]) / 2 - width / 2 : anchor - width / 2,
    };

    _y += metrics.noteGap;
    _content.add(DiagramBox(rect: Rect.fromLTWH(left, _y, width, height), radius: 2, ink: DiagramInk.fill));
    _content.add(DiagramLabel(run: run, at: Offset(left + metrics.notePadding, _y + metrics.notePadding)));
    _overhang = math.max(_overhang, left + width);
    _y += height + metrics.noteGap;
  }

  void _activation(SequenceActivation step) {
    if (step.start) {
      _active.putIfAbsent(step.participant, () => []).add(_y);

      return;
    }
    _closeActivation(step.participant);
  }

  void _closeActivation(String participant) {
    final stack = _active[participant];
    if (stack == null || stack.isEmpty) {
      return;
    }
    final top = stack.removeLast();
    final x = _centres[_column[participant]!];
    _bars.add(
      DiagramBox(
        rect: Rect.fromLTWH(
          x - metrics.activation / 2,
          top,
          metrics.activation,
          math.max(_y - top, metrics.activation),
        ),
        ink: DiagramInk.bar,
      ),
    );
  }

  /// Незакрытые полосы доводятся до низа, а не роняют раскладку (§6).
  void _closeDanglingActivations() {
    for (final participant in _active.keys.toList()) {
      while ((_active[participant] ?? const []).isNotEmpty) {
        _closeActivation(participant);
      }
    }
  }

  void _block(SequenceBlock block, int depth) {
    final top = _y;
    final inset = metrics.blockInset * (depth + 1);

    // Свой список на каждый уровень: общий затирался бы вложенным блоком, и
    // черта между ветвями внешнего осталась бы точкой в нуле.
    final dividers = <(int, double)>[];

    for (var i = 0; i < block.sections.length; i++) {
      final section = block.sections[i];
      final word = i == 0 ? block.kind.keyword : _separatorWord(block.kind);
      final run = measure.run(section.label.isEmpty ? word : '$word ${section.label}', DiagramTextRole.blockLabel);

      if (i > 0) {
        // Черта между ветвями — её ширину знаем только в конце, рисуем
        // вместе с рамкой.
        _frames.add(DiagramPath(points: [Offset(0, _y), Offset(0, _y)], dashed: true, ink: DiagramInk.faint));
        dividers.add((_frames.length - 1, _y));
      }

      _content.add(DiagramLabel(run: run, at: Offset(_left() + inset + metrics.blockInset, _y), backdrop: true));
      _y += run.size.height + metrics.labelGap;

      _walk(section.steps, depth + 1);
    }

    final bottom = _y;
    final left = _left() + inset;
    final right = _right() - inset;

    _frames.add(DiagramBox(rect: Rect.fromLTRB(left, top, right, bottom), ink: DiagramInk.faint, filled: false));

    // Чертам между ветвями достались настоящие края только сейчас.
    for (final (index, y) in dividers) {
      _frames[index] = DiagramPath(points: [Offset(left, y), Offset(right, y)], dashed: true, ink: DiagramInk.faint);
    }
    _y = bottom + metrics.blockGap;
  }

  String _separatorWord(BlockKind kind) => switch (kind) {
    BlockKind.par => 'and',
    BlockKind.critical => 'option',
    _ => 'else',
  };

  double _left() => _centres.first - _widths.first / 2 - metrics.blockInset;

  double _right() => math.max(_centres.last + _widths.last / 2, _overhang) + metrics.blockInset;

  void _drawHeaders() {
    for (var i = 0; i < _headers.length; i++) {
      final run = _headers[i];
      final rect = Rect.fromLTWH(_centres[i] - _widths[i] / 2, metrics.margin, _widths[i], _headerHeight());
      _lifelines.add(DiagramBox(rect: rect, radius: 3, ink: DiagramInk.plate));
      _lifelines.add(
        DiagramLabel(run: run, at: Offset(rect.center.dx - run.size.width / 2, rect.center.dy - run.size.height / 2)),
      );
    }
  }

  void _drawLifelines(double bottom) {
    for (var i = 0; i < _centres.length; i++) {
      _lifelines.add(
        DiagramPath(
          points: [Offset(_centres[i], _headerBottom), Offset(_centres[i], bottom)],
          dashed: true,
          ink: DiagramInk.faint,
        ),
      );
    }
  }
}
