import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import '../bootstrap/backend_registrations.dart';

/// Колонки, объявленные модулями, — ядровая половина ([ColumnSorting]).
///
/// Ядру от колонки нужно одно: чем её сравнивать. Паспорт оно держит рядом
/// затем, чтобы отличить сортируемую колонку от несортируемой и незнакомую —
/// от объявленной (`docs/spec/column-registry.md`, §5).
class ColumnSortingRegistry implements ColumnSorting {
  ColumnSortingRegistry(this._services, [List<ColumnDeclaration> columns = const []])
    : _columns = List.unmodifiable(columns),
      _byId = {for (final column in columns) column.spec.id: column};

  final FcServices _services;
  final List<ColumnDeclaration> _columns;
  final Map<String, ColumnDeclaration> _byId;

  /// Разрешённые сравнения: фабрику зовут один раз.
  ///
  /// Сравнение спрашивают на каждую перестановку списка, а служба за ним стоит
  /// одна и та же.
  final Map<String, NodeComparator?> _resolved = {};

  @override
  List<ColumnSpec> get declared => [for (final column in _columns) column.spec];

  @override
  ColumnSpec? find(String id) => _byId[id]?.spec;

  @override
  NodeComparator? comparatorOf(String id) {
    if (_resolved.containsKey(id)) {
      return _resolved[id];
    }
    final factory = _byId[id]?.compare;
    return _resolved[id] = factory == null ? null : factory(_services);
  }

  @override
  SortSpec sanitize(SortSpec spec) {
    final column = _byId[spec.column]?.spec;
    if (column != null && column.sortable) {
      return spec;
    }
    return spec.withColumn(SortSpec.defaultColumn);
  }
}

/// Ни одной объявленной колонки.
///
/// Панель без реестра — это тест состояния и сценарий: сортировать им нечем и
/// незачем, список ляжет доводчиком по имени.
class NoColumnSorting implements ColumnSorting {
  const NoColumnSorting();

  @override
  List<ColumnSpec> get declared => const [];

  @override
  ColumnSpec? find(String id) => null;

  @override
  NodeComparator? comparatorOf(String id) => null;

  @override
  SortSpec sanitize(SortSpec spec) => spec;
}
