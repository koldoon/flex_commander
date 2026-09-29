/// Модель диаграммы последовательности — чистые данные, без Flutter.
///
/// Раскладка читает её и не разбирает текст; разбор её строит и не считает
/// координат. Граница жёсткая нарочно (`docs/spec/mermaid.md`, §4).
library;

/// Чем рисуют участника.
enum ParticipantShape {
  /// Прямоугольником — `participant`.
  box,

  /// Человечком — `actor`.
  person,
}

/// Участник: столбец диаграммы.
class SequenceParticipant {
  const SequenceParticipant({required this.id, required this.label, this.shape = ParticipantShape.box});

  /// Имя, которым на него ссылаются в сообщениях.
  final String id;

  /// Подпись для человека; без псевдонима совпадает с [id].
  final String label;

  final ParticipantShape shape;

  @override
  String toString() => 'SequenceParticipant($id as $label)';
}

/// Чем кончается стрелка.
enum ArrowHead {
  /// Линия без наконечника: `->`, `-->`.
  none,

  /// Сплошной наконечник: `->>`, `-->>`.
  arrow,

  /// Крестик: `-x`, `--x`.
  cross,

  /// Открытый — «не жду ответа»: `-)`, `--)`.
  open,
}

/// Сама стрелка: рисунок линии и наконечник.
class SequenceArrow {
  const SequenceArrow({required this.head, required this.dotted});

  final ArrowHead head;

  /// Пунктиром — второй дефис в `-->`.
  final bool dotted;

  @override
  String toString() => 'SequenceArrow(${dotted ? 'dotted' : 'solid'}, $head)';
}

/// Шаг диаграммы.
sealed class SequenceStep {
  const SequenceStep();
}

/// Сообщение от участника к участнику.
class SequenceMessage extends SequenceStep {
  const SequenceMessage({
    required this.from,
    required this.to,
    required this.arrow,
    required this.label,
    this.activates = false,
    this.deactivates = false,
  });

  final String from;
  final String to;
  final SequenceArrow arrow;

  /// Подпись строками: `<br/>` уже разобран.
  final List<String> label;

  /// Краткое `+` после стрелки: открыть полосу активности у получателя.
  final bool activates;

  /// Краткое `-`: закрыть её.
  final bool deactivates;

  /// Сообщение самому себе рисуется петлёй, а не прямой.
  bool get isSelf => from == to;

  @override
  String toString() => 'SequenceMessage($from $arrow $to: ${label.join(' / ')})';
}

/// Где стоит заметка.
enum NotePlacement { leftOf, rightOf, over }

/// Заметка — врезка рядом с участником или поверх нескольких.
class SequenceNote extends SequenceStep {
  const SequenceNote({required this.placement, required this.of, required this.label});

  final NotePlacement placement;

  /// Участники, к которым она относится: один или, для `over A,B`, двое.
  final List<String> of;

  final List<String> label;

  @override
  String toString() => 'SequenceNote($placement ${of.join(',')}: ${label.join(' / ')})';
}

/// Явное открытие или закрытие полосы активности.
class SequenceActivation extends SequenceStep {
  const SequenceActivation({required this.participant, required this.start});

  final String participant;

  /// `activate` — true, `deactivate` — false.
  final bool start;

  @override
  String toString() => 'SequenceActivation(${start ? 'activate' : 'deactivate'} $participant)';
}

/// Вид рамки вокруг шагов.
enum BlockKind {
  /// Взаимоисключающие ветви: `alt` … `else` … `end`.
  alt('alt'),

  /// Необязательная ветвь: `opt` … `end`.
  opt('opt'),

  /// Повторение: `loop` … `end`.
  loop('loop'),

  /// Одновременно: `par` … `and` … `end`.
  par('par'),

  /// С оговорками: `critical` … `option` … `end`.
  critical('critical'),

  /// Прерывание: `break` … `end`.
  breakBlock('break');

  const BlockKind(this.keyword);

  final String keyword;
}

/// Ветвь блока: свой ярлык и свои шаги.
class SequenceSection {
  const SequenceSection({required this.label, required this.steps});

  /// Ярлык ветви — то, что написано после `alt` или `else`.
  final String label;

  final List<SequenceStep> steps;
}

/// Рамка: `alt`/`opt`/`loop`/`par` со своими ветвями.
///
/// Деревом, а не плоским списком с метками: незакрытый `end` тогда
/// обнаруживается разбором, а не всплывает кривой картинкой (§6).
class SequenceBlock extends SequenceStep {
  const SequenceBlock({required this.kind, required this.sections});

  final BlockKind kind;

  /// Ветви по порядку; у `opt` и `loop` она одна.
  final List<SequenceSection> sections;

  @override
  String toString() => 'SequenceBlock(${kind.keyword}, ${sections.length} ветв.)';
}

/// Разобранная диаграмма.
class SequenceDiagram {
  const SequenceDiagram({required this.participants, required this.steps, this.autonumber = false});

  /// Столбцы в порядке появления.
  final List<SequenceParticipant> participants;

  /// Шаги верхнего уровня.
  final List<SequenceStep> steps;

  /// Нумеровать ли сообщения.
  final bool autonumber;
}
