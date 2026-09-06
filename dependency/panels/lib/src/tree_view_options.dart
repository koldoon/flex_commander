import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки дерева — то, что окно выбора показывает под списком.
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

    return FcForm(
      rows: [
        CommandDialogField.wide(
          child: FcCheckbox(
            label: strings.tr('Panel follows the cursor'),
            value: settings.treeFollowsCursor,
            onChanged: (value) {
              setState(() => settings.treeFollowsCursor = value);
              widget.save();
            },
          ),
        ),
      ],
    );
  }
}
