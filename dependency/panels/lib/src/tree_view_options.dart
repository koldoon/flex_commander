import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки дерева — то, что окно выбора показывает под списком.
///
/// Пока одна: показывать ли размер. Правит раздел модуля напрямую — настройки
/// вида общие на приложение (`docs/spec/panel-views.md`, §7).
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
        CommandDialogField.wide(
          child: FcCheckbox(
            label: strings.tr('Show sizes'),
            value: settings.treeSize,
            onChanged: (value) {
              setState(() => settings.treeSize = value);
              widget.save();
            },
          ),
        ),
      ],
    );
  }
}
