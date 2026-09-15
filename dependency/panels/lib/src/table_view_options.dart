import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_table_header.dart';

/// Настройки таблицы — то, что окно выбора вида показывает под списком.
///
/// Колонки: какие видны и как вернуть умолчание. Правит **панель**, а не раздел
/// модуля: раскладка колонок у левой и правой своя, и окно открыто для одной из
/// них (`docs/spec/panel-views.md`, §7). Правит по «OK», а не живьём: до него
/// галочки ходят по черновику.
///
/// Порядок и ширина колонок здесь не показаны: их двигают прямо в шапке
/// таблицы, мышью, и второго способа тому же делу заводить незачем.
class TableViewOptions extends StatefulWidget {
  const TableViewOptions({super.key, required this.panel, required this.draft});

  /// Чья раскладка правится: сама панель, а у комбинированного вида — столбец
  /// списка (`docs/spec/panel-view-combined.md`, §7).
  final Session panel;

  final ViewOptionsDraft draft;

  @override
  State<TableViewOptions> createState() => _TableViewOptionsState();
}

class _TableViewOptionsState extends State<TableViewOptions> {
  /// Раскладка, какой она станет по «OK». Снимается с панели один раз: пока
  /// окно открыто, правит её отсюда никто, кроме этих же галочек.
  late ColumnLayout _layout = widget.panel.columns;

  void _toggle(ColumnSpec column) {
    setState(() => _layout = _layout.toggleVisible(column.id));
    widget.draft.onApply(() => widget.panel.setColumnLayout(_layout));
  }

  void _setFormat(ColumnSpec column, String format) {
    setState(() => _layout = _layout.setFormat(column.id, format));
    widget.draft.onApply(() => widget.panel.setColumnLayout(_layout));
  }

  @override
  Widget build(BuildContext context) => _form(context);

  /// Ширина столбца флажков — по самому широкому из них.
  double _labelWidth(BuildContext context, ColumnLayout layout) {
    final strings = context.strings;
    var width = 0.0;
    for (final column in layout.columns) {
      final own = FcCheckbox.widthOf(context, strings.tr(_titleOf(column)));
      if (own > width) {
        width = own;
      }
    }
    return width;
  }

  /// Название колонки для списка: у значка своего нет.
  static String _titleOf(ColumnSpec column) {
    final title = FileTableHeaderCell.titleOf(column);
    return title.isEmpty ? 'Icon' : title;
  }

  Widget _form(BuildContext context) {
    final strings = context.strings;
    final theme = FcTheme.of(context);
    final layout = _layout;

    return FcForm(
      rows: [
        // Подписью **над** столбцом: колонок девять, и в столбце значений они
        // встали бы отбитыми от левого края на ширину подписи.
        CommandDialogField.stacked(
          label: strings.tr('Columns visible'),
          children: [
            for (final column in layout.columns)
              Row(
                // По содержимому: ряд, растянутый на всю панель, уводил бы
                // списки к её правому краю, и таблица читалась бы разреженной.
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ширина — по самому широкому флажку: так списки встают
                  // колонкой, а не лесенкой за подписями разной длины. Считается
                  // на месте, потому что подписи переводятся
                  // (`docs/spec/column-formats.md`, §5).
                  // Гнётся: в узком окне столбец обязан ужаться, а не вылезти
                  // за край — заданную ширину `SizedBox` отдаёт, когда её
                  // больше, чем дали.
                  Flexible(
                    child: SizedBox(
                      width: _labelWidth(context, layout),
                      child: FcCheckbox(
                        // У колонки значка заголовка нет — в шапке ему негде
                        // стоять, — но безымянный флажок в списке читался бы
                        // сбоем.
                        label: strings.tr(_titleOf(column)),
                        value: column.visible,
                        // Иконку и имя скрывать нельзя: без них строка
                        // нечитаема.
                        onChanged: column.pinned ? null : (_) => _toggle(column),
                      ),
                    ),
                  ),
                  // Формат — там же, где видимость: всё про колонки в одном
                  // месте (`docs/spec/column-formats.md`, §5). У колонки без
                  // форматов списка нет вовсе — выбор из одного был бы обманом.
                  if (column.formats.isNotEmpty) ...[
                    SizedBox(width: theme.metrics.columnGap),
                    // Не гнётся: внутри списка ужиматься нечему — подпись и
                    // галочка стоят в строку, и сжатие ломает его раскладку.
                    // Место уступает столбец флажков.
                    FcSelect<String>(
                      value: column.effectiveFormat,
                      // Подписи форматов приходят значением — переводит их тот,
                      // кто показывает.
                      options: {for (final format in column.formats) format.id: strings.tr(format.title)},
                      onChanged: (value) => _setFormat(column, value),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ],
    );
  }
}
