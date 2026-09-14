import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки краткого вида — то, что окно выбора показывает под списком.
///
/// Число столбцов: `0` — сколько влезет. Правит раздел модуля: настройки вида
/// общие на приложение, — но по «OK», а не живьём
/// (`docs/spec/panel-views.md`, §7).
class BriefViewOptions extends StatefulWidget {
  const BriefViewOptions({super.key, required this.settings, required this.save, required this.draft});

  final PanelsSettings Function() settings;
  final VoidCallback save;
  final ViewOptionsDraft draft;

  @override
  State<BriefViewOptions> createState() => _BriefViewOptionsState();
}

class _BriefViewOptionsState extends State<BriefViewOptions> {
  /// Сколько столбцов — каким оно станет по «OK».
  late int _columns = widget.settings().briefColumns;

  void _apply() {
    widget.settings().briefColumns = _columns;
    widget.save();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    // Своей маленькой формой: подпись и значение должны стоять столбцами, как
    // во всех окнах, а список видов над ними идёт во всю ширину и в этот
    // столбец не входит.
    return FcForm(
      rows: [
        // Подписью над списком, а не слева: тем же приёмом, что у таблицы и
        // дерева, — окна настроек вида устроены одинаково.
        CommandDialogField.stacked(
          // С оговоркой: «Columns» в справке — это колонки таблицы, а здесь
          // столбцы имён (`docs/spec/localization.md`, §3).
          label: strings.tr('Columns', context: 'brief'),
          children: [
            FcSelect<int>(
              value: _columns,
              options: {
                PanelsSettings.autoColumns: strings.tr('As many as fit'),
                for (var count = 2; count <= PanelsSettings.maxColumns; count++) count: '$count',
              },
              onChanged: (value) {
                setState(() => _columns = value);
                widget.draft.onApply(_apply);
              },
            ),
          ],
        ),
      ],
    );
  }
}
