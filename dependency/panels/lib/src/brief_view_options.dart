import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки краткого вида — то, что окно выбора показывает под списком.
///
/// Число столбцов: `0` — сколько влезет. Правит раздел модуля напрямую:
/// настройки вида общие на приложение (`docs/spec/panel-views.md`, §7).
class BriefViewOptions extends StatefulWidget {
  const BriefViewOptions({super.key, required this.settings, required this.save});

  final PanelsSettings Function() settings;
  final VoidCallback save;

  @override
  State<BriefViewOptions> createState() => _BriefViewOptionsState();
}

class _BriefViewOptionsState extends State<BriefViewOptions> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final settings = widget.settings();

    // Своей маленькой формой: подпись и значение должны стоять столбцами, как
    // во всех окнах, а список видов над ними идёт во всю ширину и в этот
    // столбец не входит.
    return FcForm(
      rows: [
        CommandDialogField(
          // С оговоркой: «Columns» в справке — это колонки таблицы, а здесь
          // столбцы имён (`docs/spec/localization.md`, §3).
          label: strings.tr('Columns', context: 'brief'),
          child: FcSelect<int>(
            value: settings.briefColumns,
            options: {
              PanelsSettings.autoColumns: strings.tr('As many as fit'),
              for (var count = 2; count <= PanelsSettings.maxColumns; count++) count: '$count',
            },
            onChanged: (value) {
              setState(() => settings.briefColumns = value);
              widget.save();
            },
          ),
        ),
      ],
    );
  }
}
