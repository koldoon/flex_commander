import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Настройки вида «Значки» — то, что окно выбора показывает под списком.
///
/// Две величины: сторона значка и место под имя. Обе — списком привычных
/// величин плюс «Своё» с числовым полем. Бегунка нет — для него нет ни дизайна,
/// ни элемента в наборе виджетов, а заводить новый вид управления ради одного
/// числа значит править дизайн-систему, а не вид панели
/// (`docs/spec/panel-view-icons.md`, §7).
class IconsViewOptions extends StatefulWidget {
  const IconsViewOptions({super.key, required this.settings, required this.save, required this.draft});

  final PanelsSettings Function() settings;
  final VoidCallback save;
  final ViewOptionsDraft draft;

  @override
  State<IconsViewOptions> createState() => _IconsViewOptionsState();
}

class _IconsViewOptionsState extends State<IconsViewOptions> {
  /// Что выбрано списком размера; [PanelsSettings.customIconTileSize] — «Своё».
  late int _size =
      PanelsSettings.iconTileSizes.contains(widget.settings().iconTileSize)
          ? widget.settings().iconTileSize
          : PanelsSettings.customIconTileSize;

  /// Что выбрано списком ширины имени; [PanelsSettings.autoNameWidth] — «Авто»,
  /// [PanelsSettings.customNameWidth] — «Своё».
  late int _width = _widthChoice(widget.settings().iconNameWidth);

  late final TextEditingController _ownSize = TextEditingController(text: '${widget.settings().iconTileSize}');

  late final TextEditingController _ownWidth = TextEditingController(text: '${_shownWidth(widget.settings())}');

  static int _widthChoice(int width) => switch (width) {
    PanelsSettings.autoNameWidth => PanelsSettings.autoNameWidth,
    _ when PanelsSettings.nameWidths.contains(width) => width,
    _ => PanelsSettings.customNameWidth,
  };

  /// Что показать в поле «Своё» для ширины имени: заданное число, а при «Авто»
  /// — наименьшее из списка, чтобы поле не встречало человека пустым.
  static int _shownWidth(PanelsSettings settings) =>
      settings.iconNameWidth > PanelsSettings.autoNameWidth ? settings.iconNameWidth : PanelsSettings.nameWidths.first;

  @override
  void dispose() {
    _ownSize.dispose();
    _ownWidth.dispose();
    super.dispose();
  }

  /// Числа разбираются **по «OK»**, а не на каждый набранный знак.
  ///
  /// Иначе стирание поля схлопывало бы размер в наименьший посреди набора, а
  /// служба значков перепрашивала бы систему на каждый знак: размер входит в
  /// ключ её кеша. Чушь и пустота оставляют прежнее значение.
  void _apply() {
    final settings = widget.settings();

    if (_size != PanelsSettings.customIconTileSize) {
      settings.iconTileSize = _size;
    } else if (int.tryParse(_ownSize.text.trim()) case final own?) {
      settings.iconTileSize = own.clamp(PanelsSettings.minIconTileSize, PanelsSettings.maxIconTileSize);
    }

    if (_width == PanelsSettings.customNameWidth) {
      if (int.tryParse(_ownWidth.text.trim()) case final own?) {
        settings.iconNameWidth = own.clamp(PanelsSettings.minNameWidth, PanelsSettings.maxNameWidth);
      }
    } else {
      settings.iconNameWidth = _width;
    }

    widget.save();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final metrics = FcTheme.of(context).metrics;

    return FcForm(
      rows: [
        // Подписью над списком, а не слева: тем же приёмом, что у таблицы,
        // краткого вида и дерева, — окна настроек вида устроены одинаково.
        CommandDialogField.stacked(
          label: strings.tr('Icon size'),
          children: [
            FcSelect<int>(
              value: _size,
              options: {
                for (final size in PanelsSettings.iconTileSizes) size: '$size',
                PanelsSettings.customIconTileSize: strings.tr('Custom'),
              },
              onChanged: (value) {
                setState(() => _size = value);
                widget.draft.onApply(_apply);
              },
            ),
            // Поле появляется по выбору «Своё» и не занимает места иначе:
            // пустая строка под списком читалась бы поломкой.
            if (_size == PanelsSettings.customIconTileSize) _own(metrics, _ownSize),
          ],
        ),
        CommandDialogField.stacked(
          // Не «ширина плитки»: плитка бывает шире — её нижний предел задаёт
          // плашка значка. Настройка про то, сколько места отведено имени.
          label: strings.tr('Name width'),
          children: [
            FcSelect<int>(
              value: _width,
              options: {
                // «Авто» первым: это умолчание, и считается оно от размера
                // значка — ручку рядом крутят чаще.
                PanelsSettings.autoNameWidth: strings.tr('Auto'),
                for (final width in PanelsSettings.nameWidths) width: '$width',
                PanelsSettings.customNameWidth: strings.tr('Custom'),
              },
              onChanged: (value) {
                setState(() => _width = value);
                widget.draft.onApply(_apply);
              },
            ),
            if (_width == PanelsSettings.customNameWidth) _own(metrics, _ownWidth),
          ],
        ),
      ],
    );
  }

  /// Поле своего числа — под списком, которому оно принадлежит.
  Widget _own(FcMetrics metrics, TextEditingController controller) => Padding(
    padding: EdgeInsets.only(top: metrics.dialogLineGap),
    child: SizedBox(
      width: metrics.dialogLabelWidth,
      child: FcTextField(controller: controller, onChanged: (_) => widget.draft.onApply(_apply)),
    ),
  );
}
