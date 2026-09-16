import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_type_icon.dart';

/// Одна плитка сетки: значок, под ним имя в две строки.
///
/// То же, чем [FileTableRow] служит списку, — с одной разницей: подсветка
/// обводит **ячейку**, а не полосу во всю ширину. Плитка и есть ячейка
/// (`docs/spec/panel-view-icons.md`, §4).
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.entry,
    required this.iconSize,
    required this.nameHeight,
    required this.marked,
    required this.underCursor,
    required this.panelActive,
    required this.width,
    this.contentOf,
    this.onTap,
  });

  final FileEntry entry;

  /// Сторона значка в точках — своя величина, не размер строки списка.
  final double iconSize;

  /// Место под имя: две строки всегда, влезло оно в одну или нет.
  ///
  /// Иначе высота плитки зависела бы от имени, а на её постоянстве держится
  /// ленивость сетки (`docs/spec/panel-view-icons.md`, §5).
  final double nameHeight;

  final bool marked;
  final bool underCursor;
  final bool panelActive;

  /// Ширина плитки: по ней режется имя.
  final double width;

  final Content Function(FileEntry entry)? contentOf;

  final VoidCallback? onTap;

  bool get _selected => underCursor && panelActive;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final style = _selected ? theme.rowStyle.copyWith(color: colors.cursorText) : theme.rowStyle;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              _selected
                  ? colors.cursorBackground
                  : marked
                  ? colors.markedBackground
                  : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding, vertical: metrics.rowGap),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Значок берётся у той же службы, что и в списке: плитка
                  // своего рисования не заводит вовсе, поэтому миниатюры потом
                  // не потребуют её правок (`docs/spec/file-icons.md`).
                  SizedBox(
                    height: iconSize,
                    child: FileTypeIcon(
                      entry: entry,
                      selected: _selected,
                      contentOf: contentOf,
                      size: iconSize,
                      // Дыры на месте значка в плитке быть не должно: у файла
                      // без правила рисуется лист бумаги.
                      fillsBlank: true,
                    ),
                  ),
                  SizedBox(height: metrics.rowGap),
                  SizedBox(
                    height: nameHeight,
                    child: FcTrimmedText(
                      text: entry.name,
                      style: style,
                      width: width - metrics.cellPadding * 2,
                      textAlign: TextAlign.center,
                      maxLines: IconTile.nameLines,
                    ),
                  ),
                ],
              ),
            ),
            // Полоса пометки поверх фона: она обязана читаться и тогда, когда
            // плитка вдобавок под курсором.
            if (marked)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: metrics.markedBarWidth,
                child: ColoredBox(color: colors.markedBar),
              ),
          ],
        ),
      ),
    );
  }

  /// Имя занимает две строки, как в Finder: одной мало половине снимков с
  /// камеры, а третья отнимает у сетки ряд.
  static const int nameLines = 2;

  /// Высота плитки — поле, значок, просвет, две строки имени.
  ///
  /// Считается в одном месте: по ней же ищут плитку под указателем и место
  /// броска, а это три обычных промаха на один просвет.
  static double height(FcMetrics metrics, double iconSize, double nameHeight) =>
      metrics.rowGap * 2 + iconSize + metrics.rowGap + nameHeight;
}
