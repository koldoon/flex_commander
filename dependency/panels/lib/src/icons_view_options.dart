import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки вида «Значки» — то, что окно выбора показывает под списком.
///
/// Размер плитки: несколько привычных величин списком плюс «Своё» с числовым
/// полем. Бегунка нет — для него нет ни дизайна, ни элемента в наборе виджетов,
/// а заводить новый вид управления ради одного числа значит править
/// дизайн-систему, а не вид панели (`docs/spec/panel-view-icons.md`, §7).
class IconsViewOptions extends StatefulWidget {
  const IconsViewOptions({super.key, required this.settings, required this.save, required this.draft});

  final PanelsSettings Function() settings;
  final VoidCallback save;
  final ViewOptionsDraft draft;

  @override
  State<IconsViewOptions> createState() => _IconsViewOptionsState();
}

class _IconsViewOptionsState extends State<IconsViewOptions> {
  /// Что выбрано списком; [PanelsSettings.customIconTileSize] — «Своё».
  late int _choice =
      PanelsSettings.iconTileSizes.contains(widget.settings().iconTileSize)
          ? widget.settings().iconTileSize
          : PanelsSettings.customIconTileSize;

  late final TextEditingController _own = TextEditingController(text: '${widget.settings().iconTileSize}');

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  /// Число разбирается **по «OK»**, а не на каждый набранный знак.
  ///
  /// Иначе стирание поля схлопывало бы размер в наименьший посреди набора, а
  /// служба значков перепрашивала бы систему на каждый знак: размер входит в
  /// ключ её кеша. Чушь и пустота оставляют прежний размер.
  void _apply() {
    final settings = widget.settings();
    if (_choice != PanelsSettings.customIconTileSize) {
      settings.iconTileSize = _choice;
    } else if (int.tryParse(_own.text.trim()) case final own?) {
      settings.iconTileSize = own.clamp(PanelsSettings.minIconTileSize, PanelsSettings.maxIconTileSize);
    }
    widget.save();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return FcForm(
      rows: [
        // Подписью над списком, а не слева: тем же приёмом, что у таблицы,
        // краткого вида и дерева, — окна настроек вида устроены одинаково.
        CommandDialogField.stacked(
          label: strings.tr('Icon size'),
          children: [
            FcSelect<int>(
              value: _choice,
              options: {
                for (final size in PanelsSettings.iconTileSizes) size: '$size',
                PanelsSettings.customIconTileSize: strings.tr('Custom'),
              },
              onChanged: (value) {
                setState(() => _choice = value);
                widget.draft.onApply(_apply);
              },
            ),
            // Поле появляется по выбору «Своё» и не занимает места иначе:
            // пустая строка под списком читалась бы поломкой.
            if (_choice == PanelsSettings.customIconTileSize) ...[
              SizedBox(height: FcTheme.of(context).metrics.dialogLineGap),
              SizedBox(
                width: FcTheme.of(context).metrics.dialogLabelWidth,
                child: FcTextField(controller: _own, onChanged: (_) => widget.draft.onApply(_apply)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
