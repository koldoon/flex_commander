import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'command_dialog.dart';

/// Строка справки: название и значение.
class HelpRow {
  const HelpRow(this.name, this.value);

  final String name;
  final String value;
}

/// Раздел справки — заголовок и строки под ним.
class HelpSection {
  const HelpSection(this.title, this.rows);

  final String title;
  final List<HelpRow> rows;
}

/// Содержимое окна справки: прокручивающаяся таблица и одна кнопка.
///
/// Размер задаёт себе само: не больше окна приложения с полями по
/// [FcMetrics.dialogScreenInset] от каждого края. Рамка окна ширину не
/// назначает — она облегает то, что ей дали, — а высоту не ограничивает вовсе,
/// поэтому длинная таблица без этого вылезла бы за экран.
class CommandDialogHelp extends StatefulWidget {
  const CommandDialogHelp({super.key, required this.sections, required this.onClose});

  final List<HelpSection> sections;
  final VoidCallback onClose;

  @override
  State<CommandDialogHelp> createState() => _CommandDialogHelpState();
}

class _CommandDialogHelpState extends State<CommandDialogHelp> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Таблицу листают клавишами: справку читают, а не заполняют.
  ///
  /// Enter и Esc сюда не попадают — они не наши; их обработает рама окна, когда
  /// событие поднимется к ней.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }

    final position = _scroll.position;
    final step = FcTheme.of(context).metrics.rowHeight;
    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => position.pixels + step,
      LogicalKeyboardKey.arrowUp => position.pixels - step,
      LogicalKeyboardKey.pageDown => position.pixels + position.viewportDimension,
      LogicalKeyboardKey.pageUp => position.pixels - position.viewportDimension,
      LogicalKeyboardKey.home => position.minScrollExtent,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) {
      return KeyEventResult.ignored;
    }

    _scroll.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;
    final screen = MediaQuery.sizeOf(context);

    // Поля от края экрана считаются для окна целиком, вместе с полосой
    // заголовка, — её рисует рама, поэтому здесь она вычитается.
    final inset = metrics.dialogScreenInset;
    final width = screen.width - inset * 2;
    final height = screen.height - inset * 2 - metrics.dialogTitleHeight;

    return ConstrainedBox(
      // Не `SizedBox`: ширину окну задаёт содержимое, а это только предел.
      // Рама измеряет содержимое (`IntrinsicWidth`) и облегает его, поэтому
      // короткая таблица даёт узкое окно, а длинная упирается в поля.
      constraints: BoxConstraints(maxWidth: width < 0 ? 0 : width, maxHeight: height < 0 ? 0 : height),
      child: SizedBox(
        // Ширина берётся у самого широкого раздела: строки внутри растягиваются
        // на всё, что им дали, и сами по себе ничего не требуют.
        width: double.infinity,
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.only(
                    left: metrics.dialogHorizontalPadding,
                    right: metrics.dialogHorizontalPadding,
                    // Сверху больше: содержимое отходит от полосы заголовка.
                    top: metrics.dialogContentTopPadding,
                    bottom: metrics.dialogPadding,
                  ),
                  child: _HelpTable(sections: widget.sections),
                ),
              ),
              // Тот же ряд, что и у остальных окон: кнопка по размеру подписи,
              // прижата вправо. Своей разметкой её обходить нельзя — `FcButton`
              // под ограниченной шириной растягивается во всю её ширину.
              CommandDialogActions(actions: [FcButton(label: 'Close', onPressed: widget.onClose, primary: true)]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Таблица справки: два столбца, оба по своему содержимому.
///
/// Одна таблица на все разделы, а не по таблице на раздел: столбцы должны
/// стоять на одной вертикали через всё окно. Ширина столбца — по самой длинной
/// строке в нём (`IntrinsicColumnWidth`), поэтому окно получается ровно таким,
/// каким его делает содержимое, и ни точкой шире.
class _HelpTable extends StatelessWidget {
  const _HelpTable({required this.sections});

  final List<HelpSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          // Разделы отбиваются пустой строкой, а не отступом у заголовка:
          // в таблице отступы задаются ячейками.
          if (i > 0) _spacer(metrics.dialogGap),
          _row(
            Text(sections[i].title, style: theme.dialogTitleStyle),
            const SizedBox.shrink(),
            gap: metrics.dialogGap,
            bottom: metrics.dialogPadding / 2,
          ),
          for (final row in sections[i].rows)
            _row(
              Text(row.name, style: theme.dialogLabelStyle),
              Text(row.value, style: theme.dialogTextStyle),
              gap: metrics.dialogGap,
              bottom: metrics.dialogPadding / 4,
            ),
        ],
      ],
    );
  }

  TableRow _spacer(double height) => TableRow(children: [SizedBox(height: height), SizedBox(height: height)]);

  TableRow _row(Widget name, Widget value, {required double gap, required double bottom}) {
    return TableRow(
      children: [
        Padding(padding: EdgeInsets.only(right: gap, bottom: bottom), child: name),
        Padding(padding: EdgeInsets.only(bottom: bottom), child: value),
      ],
    );
  }
}
