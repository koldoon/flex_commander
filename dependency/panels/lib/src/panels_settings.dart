import 'package:fc_api/fc_api.dart';

/// Настройки видов панели.
///
/// Общие на приложение, а не на панель: две панели с разным числом колонок в
/// кратком виде выглядели бы поломкой, а не настройкой
/// (`docs/spec/panel-views.md`, §7).
class PanelsSettings implements Serializable {
  PanelsSettings({this.briefColumns = autoColumns, this.treeFollowsCursor = true});

  /// «Сколько влезет»: число столбцов краткого вида считается по самому
  /// длинному имени в каталоге.
  static const int autoColumns = 0;

  /// Больше восьми столбцов имён не читаются вовсе — это уже не список, а
  /// сетка обрубков.
  static const int maxColumns = 8;

  /// Сколько столбцов у краткого вида; [autoColumns] — сколько влезет.
  int briefColumns;

  /// Идёт ли панель за курсором дерева.
  ///
  /// Выключают на медленном источнике: каждый шаг стрелкой — это чтение
  /// каталога по сети, и лучше пройти дерево молча, а прочитать один раз
  /// (`docs/spec/panel-view-tree.md`, §7).
  bool treeFollowsCursor;

  @override
  void fromMap(Map<String, dynamic> m) {
    briefColumns = extract(briefColumns, m['briefColumns']).clamp(autoColumns, maxColumns);
    treeFollowsCursor = extract(treeFollowsCursor, m['treeFollowsCursor']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['briefColumns'] = briefColumns;
    m['treeFollowsCursor'] = treeFollowsCursor;
  }
}
