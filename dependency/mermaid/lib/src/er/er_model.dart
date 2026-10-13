/// Модель ER-диаграммы — чистые данные, без Flutter (`docs/spec/mermaid.md`,
/// §4, §7а).
library;

import '../flowchart/flowchart_model.dart';

/// Ключ атрибута.
enum ErKey {
  pk('PK'),
  fk('FK'),
  uk('UK');

  const ErKey(this.keyword);

  /// Как его пишут и показывают.
  final String keyword;
}

/// Сколько экземпляров на этом конце связи — нотация crow's foot.
enum ErCard {
  /// `|o` / `o|` — ноль или один.
  zeroOrOne,

  /// `||` — ровно один.
  exactlyOne,

  /// `}o` / `o{` — ноль или много.
  zeroOrMore,

  /// `}|` / `|{` — один или много.
  oneOrMore,
}

/// Атрибут сущности: строка её таблицы.
class ErAttribute {
  const ErAttribute({required this.type, required this.name, this.keys = const [], this.comment = ''});

  final String type;
  final String name;

  /// Ключи в том порядке, в каком их написали.
  final List<ErKey> keys;

  /// Комментарий; пусто — его нет.
  final String comment;

  @override
  String toString() => 'ErAttribute($type $name ${keys.map((key) => key.keyword).join(',')} "$comment")';
}

/// Сущность — таблица.
class ErEntity {
  const ErEntity({required this.id, required this.label, required this.attributes});

  /// Имя, которым на неё ссылаются связи.
  final String id;

  /// Что писать в шапке: псевдоним `p[Person]`, а нет его — имя.
  final String label;

  final List<ErAttribute> attributes;

  @override
  String toString() => 'ErEntity($id, атрибутов ${attributes.length})';
}

/// Связь двух сущностей.
class ErRelation {
  const ErRelation({
    required this.from,
    required this.to,
    required this.fromCard,
    required this.toCard,
    required this.identifying,
    required this.label,
  });

  /// Левая сущность записи.
  final String from;

  /// Правая.
  final String to;

  /// Кардинальность у [from] — та, что записана слева от линии.
  final ErCard fromCard;

  /// Кардинальность у [to].
  final ErCard toCard;

  /// `--` — идентифицирующая, сплошная; `..` — нет, пунктир.
  final bool identifying;

  /// Подпись; пусто — её нет.
  final String label;

  @override
  String toString() => 'ErRelation($from $fromCard ${identifying ? '--' : '..'} $toCard $to : $label)';
}

/// Разобранный `erDiagram`.
class ErDiagram {
  const ErDiagram({required this.direction, required this.entities, required this.relations});

  /// Куда растёт картинка — то же, что у графа: раскладка у них общая.
  final FlowDirection direction;

  /// Сущности в порядке первой встречи: с него начинается порядок в слое.
  final List<ErEntity> entities;

  final List<ErRelation> relations;

  @override
  String toString() => 'ErDiagram(${direction.keyword}, сущностей ${entities.length}, связей ${relations.length})';
}
