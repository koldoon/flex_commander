import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import '../bootstrap/frontend_registrations.dart';

/// Колонки, объявленные модулями, — экранная половина ([PanelColumns]).
///
/// Своих колонок у ядра нет ни одной: штатные десять приносит модуль панелей,
/// как и саму таблицу. Отключён он — колонок нет вовсе, и это честно: рисовать
/// их всё равно нечем (`docs/spec/column-registry.md`, §7).
class ColumnRegistry implements PanelColumns {
  ColumnRegistry([List<ColumnDeclaration> columns = const []])
    : _columns = List.unmodifiable(columns),
      _byId = {for (final column in columns) column.spec.id: column};

  final List<ColumnDeclaration> _columns;
  final Map<String, ColumnDeclaration> _byId;

  @override
  List<ColumnSpec> get declared => [for (final column in _columns) column.spec];

  @override
  ColumnSpec? find(String id) => _byId[id]?.spec;

  @override
  ColumnText? textOf(String id) => _byId[id]?.text;

  @override
  ColumnCellBuilder? builderOf(String id) => _byId[id]?.build;

  @override
  ColumnLayout resolve(ColumnLayout layout, {Set<String> extra = const {}}) =>
      layout.resolvedWith(declared, extra: extra);
}

/// Ни одной объявленной колонки.
///
/// Зеркалу без реестра — проверке одной панели, сценарию — рисовать нечем:
/// раскладка выходит пустой, и таблица встаёт без единой колонки.
class NoPanelColumns implements PanelColumns {
  const NoPanelColumns();

  @override
  List<ColumnSpec> get declared => const [];

  @override
  ColumnSpec? find(String id) => null;

  @override
  ColumnText? textOf(String id) => null;

  @override
  ColumnCellBuilder? builderOf(String id) => null;

  @override
  ColumnLayout resolve(ColumnLayout layout, {Set<String> extra = const {}}) => layout;
}
