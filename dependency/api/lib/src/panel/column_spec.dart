import '../serialization.dart';

/// Идентификатор колонки панели.
///
/// Значения сохраняются в настройках по имени, поэтому переименовывать их
/// нельзя — только добавлять новые.
/// Название колонки для показа пользователю.
///
/// Живёт рядом с самой колонкой, а не в виджете таблицы: то же название нужно
/// справке, списку команд и любому модулю, который рисует своё содержимое
/// панели, — а тащить ради строки виджет ядра незачем.
extension FsColumnTitle on FsColumn {
  String get title => switch (this) {
    FsColumn.icon => '',
    FsColumn.name => 'Name',
    FsColumn.ext => 'Ext',
    FsColumn.size => 'Size',
    FsColumn.modified => 'Modified',
    FsColumn.created => 'Created',
    FsColumn.accessed => 'Accessed',
    FsColumn.attributes => 'Attributes',
  };
}

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

  int indexOf(FsColumn id) => columns.indexWhere((column) => column.id == id);

  /// Первая позиция, куда можно перетащить колонку: обязательные колонки
  /// (иконка и имя) всегда остаются слева.
  int get firstMovableIndex {
    var index = 0;
    for (var i = 0; i < columns.length; i++) {
      if (columns[i].pinned) {
        index = i + 1;
      }
    }
    return index;
  }

  /// Переставляет колонку так, чтобы её итоговая позиция стала [to].
  /// Обязательные колонки не двигаются и не пропускают другие вперёд себя.
  ColumnLayout moveColumn(int from, int to) {
    if (from == to || from < 0 || from >= columns.length || columns[from].pinned) {
      return this;
    }

    final result = columns.toList();
    final spec = result.removeAt(from);
    result.insert(to.clamp(firstMovableIndex, result.length), spec);
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

  /// Ширина сохраняется только у тех колонок, которые пользователь может
  /// менять: у закреплённых её всё равно задаёт приложение (см. [fromJson]).
  List<Map<String, Object?>> toJson() => [
    for (final column in columns)
      {'id': column.id.name, if (!column.pinned) 'width': column.width, 'visible': column.visible},
  ];

  /// Восстановление раскладки из настроек.
  ///
  /// Основой всегда служит [defaults]: из файла берутся только порядок, ширина
  /// и видимость известных колонок. Неизвестные записи игнорируются, а колонки,
  /// появившиеся в новых версиях, добавляются в конец — поэтому старый файл
  /// настроек не мешает добавлять колонки.
  ///
  /// **Ширина закреплённых колонок из файла не берётся.** Менять её пользователь
  /// не может — у иконки нет ручки, а имя «резиновое», — зато задаёт приложение,
  /// исходя из размера глифа и отступов. Если читать её из настроек, однажды
  /// сохранённое значение осталось бы навсегда и правки оформления до
  /// пользователя не дошли бы.
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
      final id = FsColumn.byName(extract('', item['id']));
      final spec = id == null ? null : byId.remove(id);
      if (spec == null) {
        continue;
      }
      restored.add(
        spec.copyWith(
          // Значения читаются конверторами пакета: чего в файле нет, остаётся
          // как в умолчаниях.
          width: spec.pinned ? null : extract(spec.width, item['width']),
          visible: spec.pinned ? true : extract(spec.visible, item['visible']),
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
    // Ширины — по референсу с тем же коэффициентом, что и остальные размеры
    // (см. `FcMetrics.scale`): колонка иконки вмещает отступ, глиф и просвет
    // до имени, размер — `width="160"`, дата — `width="220"`.
    // Иконка: отступ слева, глиф и просвет до имени — `FcMetrics.iconColumnWidth`.
    ColumnSpec(id: FsColumn.icon, width: 28, minWidth: 28, pinned: true),
    ColumnSpec(id: FsColumn.name, width: 0, minWidth: 90, pinned: true),
    ColumnSpec(id: FsColumn.ext, width: 40, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.size, width: 64, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.modified, width: 88, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.created, width: 88, visible: false, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.accessed, width: 88, visible: false, align: ColumnAlign.end),
    ColumnSpec(id: FsColumn.attributes, width: 88, visible: false),
  ]);
}
