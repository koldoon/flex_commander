import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки дерева — то, что окно выбора показывает под списком.
///
/// Колонками, а не флажками вразнобой: размер в дереве — это колонка, и рядом
/// с ним встанут дата и остальное, когда до них дойдёт черёд. Группой, а не
/// блоком строк: флажки — самостоятельные управления, и просвет между ними
/// обычный, окошный
/// (`docs/spec/panel-view-tree.md`, §4). Правит раздел модуля: настройки вида
/// общие на приложение, — но по «OK», а не живьём (`docs/spec/panel-views.md`,
/// §7).
class TreeViewOptions extends StatefulWidget {
  const TreeViewOptions({super.key, required this.settings, required this.save, required this.draft});

  final PanelsSettings Function() settings;
  final VoidCallback save;
  final ViewOptionsDraft draft;

  @override
  State<TreeViewOptions> createState() => _TreeViewOptionsState();
}

class _TreeViewOptionsState extends State<TreeViewOptions> {
  /// Показывать ли размер — каким оно станет по «OK».
  late bool _size = widget.settings().treeSize;

  void _apply() {
    widget.settings().treeSize = _size;
    widget.save();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    // Своей маленькой формой — как у краткого вида: список видов над ней идёт
    // во всю ширину и в столбец подписей не входит.
    return FcForm(
      rows: [
        CommandDialogField.stacked(
          // Тем же приёмом, что у таблицы: подпись над столбцом флажков.
          label: strings.tr('Columns visible'),
          children: [
            FcCheckbox(
              label: strings.tr('Size'),
              value: _size,
              onChanged: (value) {
                setState(() => _size = value);
                widget.draft.onApply(_apply);
              },
            ),
            // Показан, но не работает: место под будущую колонку занято, и
            // видно, что оно занято нарочно. Обещать её флажком, который
            // ничего не меняет, нельзя — поэтому он выключен и снят
            // (`docs/spec/panel-view-tree.md`, §4).
            FcCheckbox(label: strings.tr('Modified (not implemented)'), value: false, onChanged: null),
          ],
        ),
      ],
    );
  }
}
