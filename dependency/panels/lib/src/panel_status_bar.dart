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
                  child:
                      panel.quickSearch == null
                          ? Text.rich(
                            _content(theme),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: error ? theme.statusStyle.copyWith(color: theme.colors.error) : theme.statusStyle,
                          )
                          : _search(theme, panel.quickSearch!),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Набранное в быстром поиске — **полем ввода**, а не строкой текста.
  ///
  /// Рамка здесь не украшение: пока идёт поиск, клавиши принадлежат ему, и
  /// человек должен видеть, куда они уходят. Строкой текста это выглядело бы
  /// как сообщение, а сообщения ввод не забирают.
  ///
  /// Поле ненастоящее: клавиши разбирает приложение, а не текстовое поле
  /// системы. Настоящее пришлось бы ещё и фокусировать, отбирая его у панели, —
  /// а курсор при этом обязан оставаться на своём месте в списке.
  Widget _search(FcTheme theme, String pattern) {
    final metrics = theme.metrics;
    final colors = theme.colors;

    return Row(
      children: [
        Text('Search', style: theme.statusStyle.copyWith(color: colors.secondaryText)),
        SizedBox(width: metrics.columnGap),
        Flexible(
          child: Container(
            // Той же высоты, что поля в окнах: поле должно выглядеть полем, а
            // не сжатой его копией. Ради этого и подросла сама полоса.
            height: metrics.inputHeight,
            padding: EdgeInsets.symmetric(horizontal: metrics.inputHorizontalPadding),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: colors.inputBackground,
              border: Border.all(color: colors.focusRing, width: metrics.strokeWidth),
              borderRadius: BorderRadius.circular(metrics.inputRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(pattern, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.inputStyle)),
                // Курсор — чтобы ввод был виден сразу, а не угадывался по
                // рамке. Не мигает нарочно: мигание — бесконечная анимация, и
                // `pumpAndSettle` в тестах не дождался бы её никогда.
                Padding(
                  padding: EdgeInsets.only(left: metrics.strokeWidth),
                  child: SizedBox(
                    // Вдвое толще линии: волосяной курсор на общем фоне не
                    // виден, а толще — уже похож на знак.
                    width: metrics.strokeWidth * 2,
                    height: metrics.fontSize,
                    child: ColoredBox(color: colors.inputText),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: metrics.columnGap),
        // Выход только по `Esc` — и об этом сказано прямо: пока поле на экране,
        // клавиши не вернутся к панели сами.
        Text('Esc to leave', style: theme.statusStyle.copyWith(color: colors.secondaryText)),
      ],
    );
  }

  InlineSpan _content(FcTheme theme) {
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
