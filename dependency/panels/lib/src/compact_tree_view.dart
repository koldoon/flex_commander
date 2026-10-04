import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';
import 'tree_view.dart';

/// Сжатое дерево: цепочка каталогов с единственным подкаталогом стоит одной
/// строкой — `src/main/java/com/acme` (`docs/spec/panel-view-compact-tree.md`).
///
/// Отдельный вид, а не настройка дерева: обычное дерево не меняется вовсе, и
/// кому привычна лестница, тот её и оставит. Рисует его та же отрисовка, что и
/// дерево, — разница только в строках, а их склеивает ядро: курсор и команды
/// дерева ходят по его строкам, и склейка в одном виде уводила бы стрелки в
/// спрятанные ступени (§9).
class CompactTreeView extends StatelessWidget {
  const CompactTreeView({super.key, required this.panel, required this.settings});

  static const String viewId = 'compactTree';

  final Session panel;
  final PanelsSettings Function() settings;

  @override
  Widget build(BuildContext context) => TreeView(panel: panel, settings: settings, rows: RowsKind.compactTree);
}
