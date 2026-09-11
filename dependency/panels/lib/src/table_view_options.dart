import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_table_header.dart';

/// Настройки таблицы — то, что окно выбора вида показывает под списком.
///
/// Колонки: какие видны и как вернуть умолчание. Правит **панель**, а не раздел
/// модуля: раскладка колонок у левой и правой своя, и окно открыто для одной из
/// них (`docs/spec/panel-views.md`, §7).
///
/// Порядок и ширина колонок здесь не показаны: их двигают прямо в шапке
/// таблицы, мышью, и второго способа тому же делу заводить незачем.
class TableViewOptions extends StatelessWidget {
  const TableViewOptions({super.key, required this.panel});

  final Session panel;

  @override
  Widget build(BuildContext context) {
    // Своего состояния нет: раскладка живёт в панели, и перерисовка приходит
    // оттуда же — тем же способом, каким её слушает сама таблица.
    return ListenableBuilder(listenable: panel, builder: (context, _) => _form(context));
  }

  /// Название колонки для списка: у значка своего нет.
  static String _titleOf(ColumnSpec column) {
    final title = FileTableHeaderCell.titleOf(column);
    return title.isEmpty ? 'Icon' : title;
  }

  Widget _form(BuildContext context) {
    final strings = context.strings;
    final layout = panel.columns;

    return FcForm(
      rows: [
        // Подписью **над** столбцом: колонок девять, и в столбце значений они
        // встали бы отбитыми от левого края на ширину подписи.
        CommandDialogField.stacked(
          label: strings.tr('Columns visible'),
          children: [
            for (final column in layout.columns)
              FcCheckbox(
                // У колонки значка заголовка нет — в шапке ему негде стоять, —
                // но безымянный флажок в списке читался бы сбоем.
                label: strings.tr(_titleOf(column)),
                value: column.visible,
                // Иконку и имя скрывать нельзя: без них строка нечитаема.
                onChanged: column.pinned ? null : (_) => panel.setColumnLayout(panel.columns.toggleVisible(column.id)),
              ),
          ],
        ),
      ],
    );
  }
}
