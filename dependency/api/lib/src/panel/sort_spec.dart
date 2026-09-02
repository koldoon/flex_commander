import '../serialization.dart';
import 'column_spec.dart';

enum SortDirection {
  ascending,
  descending;

  SortDirection get opposite => this == ascending ? descending : ascending;
}

/// Правило сортировки списка панели.
class SortSpec {
  const SortSpec({this.column = FsColumn.name, this.direction = SortDirection.ascending, this.foldersFirst = true});

  final FsColumn column;
  final SortDirection direction;

  /// Каталоги всегда выше файлов, независимо от колонки и направления.
  final bool foldersFirst;

  /// Клик по заголовку: та же колонка — смена направления, другая — она же
  /// по возрастанию.
  SortSpec toggled(FsColumn other) {
    if (other == column) {
      return SortSpec(column: column, direction: direction.opposite, foldersFirst: foldersFirst);
    }
    return SortSpec(column: other, direction: SortDirection.ascending, foldersFirst: foldersFirst);
  }

  Map<String, Object?> toJson() => {'column': column.name, 'direction': direction.name, 'foldersFirst': foldersFirst};

  /// Разбор настроек: непонятные значения заменяются умолчаниями, а не роняют
  /// загрузку.
  factory SortSpec.fromJson(Object? json) {
    if (json is! Map) {
      return const SortSpec();
    }
    const fallback = SortSpec();
    // Значения читаются конверторами пакета; перечислимые типы он не знает,
    // поэтому имя колонки и направление сводятся к допустимым здесь.
    final column = FsColumn.byName(extract('', json['column']));

    return SortSpec(
      column: column != null && column.sortable ? column : fallback.column,
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
  String toString() => 'SortSpec(${column.name}, ${direction.name})';
}
