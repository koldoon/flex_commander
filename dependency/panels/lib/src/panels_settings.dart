import 'package:fc_api/fc_api.dart';

/// Настройки видов панели.
///
/// Общие на приложение, а не на панель: две панели с разным числом колонок в
/// кратком виде выглядели бы поломкой, а не настройкой
/// (`docs/spec/panel-views.md`, §7).
class PanelsSettings implements Serializable {
  PanelsSettings({this.briefColumns = autoColumns, this.treeSize = true, this.cursorHoldsPlace = true});

  /// «Сколько влезет»: число столбцов краткого вида считается по самому
  /// длинному имени в каталоге.
  static const int autoColumns = 0;

  /// Больше восьми столбцов имён не читаются вовсе — это уже не список, а
  /// сетка обрубков.
  static const int maxColumns = 8;

  /// Сколько столбцов у краткого вида; [autoColumns] — сколько влезет.
  int briefColumns;

  /// Показывать ли размер в дереве.
  ///
  /// Включено: размер — то, ради чего каталог и помечают
  /// (`docs/spec/panel-view-tree.md`, §4).
  bool treeSize;

  /// Держать строку под курсором на месте, когда список переставили.
  ///
  /// Включено: перестановку человек попросил, а вот терять из виду то, на что
  /// он смотрит, не просил (`docs/spec/panel-views.md`, §9). Выключенное
  /// возвращает прежнюю минимальную подмотку: список стоит, курсор уезжает.
  bool cursorHoldsPlace;

  @override
  void fromMap(Map<String, dynamic> m) {
    briefColumns = extract(briefColumns, m['briefColumns']).clamp(autoColumns, maxColumns);
    treeSize = extract(treeSize, m['treeSize']);
    cursorHoldsPlace = extract(cursorHoldsPlace, m['cursorHoldsPlace']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['briefColumns'] = briefColumns;
    m['treeSize'] = treeSize;
    m['cursorHoldsPlace'] = cursorHoldsPlace;
  }
}
