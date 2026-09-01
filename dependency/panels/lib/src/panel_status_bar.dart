import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Строка состояния под списком.
///
/// Что показывается, по убыванию приоритета: текст, выставленный командой →
/// сводка по помеченным объектам → сведения об объекте под курсором.
/// Правила взяты из `getSelectionInfoText` референса.
class PanelStatusBar extends StatelessWidget {
  const PanelStatusBar({super.key, required this.panel});

  final Panel panel;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([panel, panel.selection]),
      builder: (context, _) {
        final error = panel.status == PanelStatus.error;
        final stroke = theme.metrics.strokeWidth;

        return SizedBox(
          height: theme.metrics.statusBarHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Линейка не доходит до рамки панели — ровно на её толщину, как в
              // референсе. Дойди она до края, получился бы угол, и полоса
              // читалась бы отдельной коробкой, а не низом той же панели.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: stroke),
                child: SizedBox(height: stroke, child: ColoredBox(color: theme.colors.columnDivider)),
              ),
              Expanded(
                child: Container(
                  // Поле слева и справа: рамка полосы и текст не должны
                  // сходиться вплотную. Ролями, а не числом, — иначе отступ
                  // останется прежним при любом масштабе темы, а всё вокруг
                  // него уедет (`DefaultMetrics(scale: 0.8)` — это «крупная»
                  // тема).
                  padding: EdgeInsets.symmetric(horizontal: theme.metrics.labelPadding + theme.metrics.cellPadding),
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    _content(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: error ? theme.statusStyle.copyWith(color: theme.colors.error) : theme.statusStyle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  InlineSpan _content(FcTheme theme) {
    // Быстрый поиск — впереди всего: пока набирают имя, строка состояния
    // показывает набранное, а не то, что под курсором. Оно и так видно —
    // курсор стоит на нём.
    final search = panel.quickSearch;
    if (search != null) {
      return TextSpan(
        children: [
          TextSpan(text: 'Search: ', style: TextStyle(color: theme.colors.secondaryText)),
          TextSpan(text: search),
        ],
      );
    }

    final status = panel.statusText;
    if (status != null && status.isNotEmpty) {
      return TextSpan(text: status);
    }

    final selection = panel.selection;
    if (selection.isNotEmpty) {
      final size = panel.selectionSize;
      final items = 'Selected ${selection.length} ${selection.length == 1 ? 'item' : 'items'}';
      // Каталоги обходятся фоном, и пока обход идёт, сумма неполная —
      // сказать об этом надо прямо, иначе растущее число выглядит ошибкой.
      final scanning = panel.selectionSizeIsFinal ? '' : ' (Scanning…)';
      return TextSpan(text: size > 0 ? '$items, ${formatBytesLong(size)}$scanning' : '$items$scanning');
    }

    final node = panel.currentNode;
    if (node is LinkNode) {
      // Стрелка — глиф шрифта иконок, а не пара знаков «->»: рисованная
      // стрелка не рассыпается на разные шрифты и выглядит как стрелка.
      return TextSpan(
        children: [
          TextSpan(text: node.name),
          TextSpan(
            text: ' ${theme.icons.glyph(theme.icons.angleRight)} ',
            style: TextStyle(fontFamily: theme.icons.fontFamily),
          ),
          TextSpan(text: node.reference),
        ],
      );
    }

    return TextSpan(text: node?.name ?? '-');
  }
}
