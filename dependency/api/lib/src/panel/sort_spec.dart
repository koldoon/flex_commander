import '../serialization.dart';

enum SortDirection {
  ascending,
  descending;

  SortDirection get opposite => this == ascending ? descending : ascending;
}

/// Правило сортировки списка панели.
class SortSpec {
  const SortSpec({this.column = defaultColumn, this.direction = SortDirection.ascending, this.foldersFirst = true});

  /// Колонка, по которой список отсортирован, пока не выбрали другую.
  ///
  /// Имя, а не ссылка на объявление: колонки приносят модули, и знать их здесь
  /// некому. Это то же внешнее имя, что лежит в настройках; договорённость о
  /// нём записана в `docs/spec/column-registry.md`, §9.
  static const String defaultColumn = 'name';

  /// Имя колонки. Незнакомую сортировку не проверяем здесь: реестра
  /// объявлений в этом пакете нет, и проверяет её тот, у кого он есть, —
  /// ядро, когда собирает панель.
  final String column;
  final SortDirection direction;

  /// Каталоги всегда выше файлов, независимо от колонки и направления.
  final bool foldersFirst;

  /// Клик по заголовку: та же колонка — смена направления, другая — она же
  /// по возрастанию.
  SortSpec toggled(String other) {
    if (other == column) {
      return SortSpec(column: column, direction: direction.opposite, foldersFirst: foldersFirst);
    }
    return SortSpec(column: other, direction: SortDirection.ascending, foldersFirst: foldersFirst);
  }

  SortSpec withColumn(String other) => SortSpec(column: other, direction: direction, foldersFirst: foldersFirst);

  Map<String, Object?> toJson() => {'column': column, 'direction': direction.name, 'foldersFirst': foldersFirst};

  /// Разбор настроек: непонятные значения заменяются умолчаниями, а не роняют
  /// загрузку.
  factory SortSpec.fromJson(Object? json) {
    if (json is! Map) {
      return const SortSpec();
    }
    const fallback = SortSpec();
    final column = extract('', json['column']);

    return SortSpec(
      column: column.isEmpty ? fallback.column : column,
      direction:
          extract('', json['direction']) == SortDirection.descending.name
              ? SortDirection.descending
              : SortDirection.ascending,
      foldersFirst: extract(fallback.foldersFirst, json['foldersFirst']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SortSpec && other.column == column && other.direction == direction && other.foldersFirst == foldersFirst;

  @override
  int get hashCode => Object.hash(column, direction, foldersFirst);

  @override
  String toString() => 'SortSpec($column, ${direction.name})';
}
