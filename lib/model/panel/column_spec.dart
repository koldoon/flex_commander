/// Идентификатор колонки панели.
///
/// Значения сохраняются в настройках по имени, поэтому переименовывать их
/// нельзя — только добавлять новые.
enum FsColumn {
  icon,
  name,
  ext,
  size,
  modified,
  created,
  accessed,
  attributes;

  static FsColumn? byName(String value) {
    for (final column in values) {
      if (column.name == value) {
        return column;
      }
    }
    return null;
  }

  /// По колонке можно сортировать.
  bool get sortable => this != icon;
}

enum ColumnAlign { start, end }

/// Описание одной колонки: ширина, видимость, выравнивание.
class ColumnSpec {
  const ColumnSpec({
    required this.id,
    required this.width,
    this.minWidth = 24,
    this.visible = true,
    this.pinned = false,
    this.align = ColumnAlign.start,
  });

  final FsColumn id;

  /// Ширина в логических пикселях. Игнорируется для «резиновой» колонки [FsColumn.name].
  final double width;

  final double minWidth;

  final bool visible;

  /// Колонку нельзя скрыть или переместить: иконка и имя.
  final bool pinned;

  final ColumnAlign align;

  /// Колонка занимает всё оставшееся место.
  bool get flexible => id == FsColumn.name;

  ColumnSpec copyWith({double? width, bool? visible}) => ColumnSpec(
    id: id,
    width: width ?? this.width,
    minWidth: minWidth,
    visible: visible ?? this.visible,
    pinned: pinned,
    align: align,
  );

  @override
  String toString() => 'ColumnSpec(${id.name}, $width, visible: $visible)';
}

/// Раскладка колонок панели. Неизменяема: любое изменение даёт новую раскладку.
class ColumnLayout {
  ColumnLayout(List<ColumnSpec> columns) : columns = List.unmodifiable(columns);

  final List<ColumnSpec> columns;

  List<ColumnSpec> get visibleColumns => columns.where((c) => c.visible).toList(growable: false);

  ColumnSpec? find(FsColumn id) {
    for (final column in columns) {
      if (column.id == id) {
        return column;
      }
    }
    return null;
  }

  ColumnLayout moveColumn(int from, int to) {
    if (from == to) {
      return this;
    }
    final result = columns.toList();
    final spec = result.removeAt(from);
    result.insert(to.clamp(0, result.length), spec);
    return ColumnLayout(result);
  }

  ColumnLayout resize(FsColumn id, double width) {
    return ColumnLayout([
      for (final column in columns)
        column.id == id ? column.copyWith(width: width < column.minWidth ? column.minWidth : width) : column,
    ]);
  }

  ColumnLayout toggleVisible(FsColumn id) {
    return ColumnLayout([
      for (final column in columns)
        column.id == id && !column.pinned ? column.copyWith(visible: !column.visible) : column,
    ]);
  }

  List<Map<String, Object?>> toJson() => [
    for (final column in columns) {'id': column.id.name, 'width': column.width, 'visible': column.visible},
  ];

  /// Восстановление раскладки из настроек.
  ///
  /// Основой всегда служит [defaults]: из файла берутся только порядок, ширина
  /// и видимость известных колонок. Неизвестные записи игнорируются, а колонки,
  /// появившиеся в новых версиях, добавляются в конец — поэтому старый файл
  /// настроек не мешает добавлять колонки.
  factory ColumnLayout.fromJson(Object? json) {
    if (json is! List) {
      return defaults;
    }

    final byId = {for (final column in defaults.columns) column.id: column};
    final restored = <ColumnSpec>[];

    for (final item in json) {
      if (item is! Map) {
        continue;
      }
      final id = FsColumn.byName('${item['id']}');
      final spec = id == null ? null : byId.remove(id);
      if (spec == null) {
        continue;
      }
      final width = item['width'];
      final visible = item['visible'];
      restored.add(
        spec.copyWith(
          width: width is num ? width.toDouble() : null,
          visible: spec.pinned ? true : (visible is bool ? visible : null),
        ),
      );
    }

    if (restored.isEmpty) {
      return defaults;
    }
    // Колонки, которых не было в файле, идут следом в порядке умолчаний.
    restored.addAll(byId.values);
    return ColumnLayout(restored);
  }

  /// Раскладка по умолчанию — как в макете: иконка, имя, расширение, размер, дата.
  static ColumnLayout get defaults => ColumnLayout(const [
    ColumnSpec(id: FsColumn.icon, width: 24, minWidth: 24, pinned: true),
    ColumnSpec(id: FsColumn.name, width: 0, minWidth: 80, pinned: true),
    ColumnSpec(id: FsColumn.ext, width: 40, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.size, width: 60, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.modified, width: 78, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.created, width: 78, visible: false, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.accessed, width: 78, visible: false, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.attributes, width: 84, visible: false),
  ]);
}
