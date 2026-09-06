import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки дерева — то, что окно выбора показывает под списком.
///
/// Колонками, а не флажками вразнобой: размер в дереве — это колонка, и рядом
/// с ним встанут дата и остальное, когда до них дойдёт черёд
/// (`docs/spec/panel-view-tree.md`, §4). Правит раздел модуля напрямую:
/// настройки вида общие на приложение (`docs/spec/panel-views.md`, §7).
class TreeViewOptions extends StatefulWidget {
  const TreeViewOptions({super.key, required this.settings, required this.save});

  final PanelsSettings Function() settings;
  final VoidCallback save;

  @override
  State<TreeViewOptions> createState() => _TreeViewOptionsState();
}

class _TreeViewOptionsState extends State<TreeViewOptions> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final settings = widget.settings();

    // Своей маленькой формой — как у краткого вида: список видов над ней идёт
    // во всю ширину и в столбец подписей не входит.
    return FcForm(
      rows: [
        CommandDialogField.column(
          // Те же колонки, что у таблицы, — и слово то же.
          label: strings.tr('Columns', context: 'tree'),
          children: [
            FcCheckbox(
              label: strings.tr('Size'),
              value: settings.treeSize,
              onChanged: (value) {
                setState(() => settings.treeSize = value);
                widget.save();
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
