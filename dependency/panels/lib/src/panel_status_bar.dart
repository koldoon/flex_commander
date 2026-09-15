import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Строка состояния под списком.
///
/// Что показывается, по убыванию приоритета: текст, выставленный командой →
/// сводка по помеченным объектам → сведения об объекте под курсором.
/// Правила взяты из `getSelectionInfoText` референса.
class PanelStatusBar extends StatelessWidget {
  const PanelStatusBar({super.key, required this.panel});

  final Session panel;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) {
        final error = panel.phase == PanelPhase.error;
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
                  child: _text(context, theme, error: error),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Строка состояния с подсказкой, когда сказанное не поместилось.
  ///
  /// Сюда смотрят, когда имя в списке обрезано, — и обрезанная строка
  /// состояния оставляла бы вопрос без ответа совсем (`docs/spec/tooltips.md`,
  /// §7). `FcTrimmedText` не встаёт: текст набран кусками разных стилей.
  Widget _text(BuildContext context, FcTheme theme, {required bool error}) {
    final style = error ? theme.statusStyle.copyWith(color: theme.colors.error) : theme.statusStyle;
    final (span, whole) = _content(theme, context.strings);
    final shown = Text.rich(span, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

    // Своей раскладкой: полоса занимает всю ширину панели, и знать её заранее
    // неоткуда. Интринсиками панель никто не меряет — это не окно команды.
    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = FcTheme.effective(context, style);
        final width = spanWidthOf(TextSpan(style: measured, children: [span]), MediaQuery.textScalerOf(context));
        return fcTooltipIf(context, trimmed: width > constraints.maxWidth, message: whole, child: shown);
      },
    );
  }

  /// Что сказано — набором и теми же словами простым текстом.
  ///
  /// Двумя значениями сразу, а не двумя методами: подсказка обязана говорить
  /// **то же**, что полоса, а два места, собирающие одно, однажды разойдутся.
  (InlineSpan, String) _content(FcTheme theme, Strings strings) {
    final status = panel.statusText;
    if (status != null && status.isNotEmpty) {
      return (TextSpan(text: status), status);
    }

    final marked = panel.markedPaths;
    if (marked.isNotEmpty) {
      final size = panel.markedSize;
      final items = strings.plural(marked.length, one: 'Selected {n} item', other: 'Selected {n} items');
      // Каталоги обходятся фоном, и пока обход идёт, сумма неполная —
      // сказать об этом надо прямо, иначе растущее число выглядит ошибкой.
      final scanning = panel.markedSizeIsFinal ? '' : ' ${strings.tr('(Scanning…)')}';
      final text = size > 0 ? '$items, ${formatBytesLong(size)}$scanning' : '$items$scanning';
      return (TextSpan(text: text), text);
    }

    final entry = panel.currentEntry;
    if (entry != null && entry.isLink) {
      // Стрелка — глиф шрифта иконок, а не пара знаков «->»: рисованная
      // стрелка не рассыпается на разные шрифты и выглядит как стрелка.
      return (
        TextSpan(
          children: [
            TextSpan(text: entry.name),
            TextSpan(
              text: ' ${theme.icons.glyph(theme.icons.angleRight)} ',
              style: TextStyle(fontFamily: theme.icons.fontFamily),
            ),
            TextSpan(text: entry.reference),
          ],
        ),
        // В подсказке стрелка — обычный знак: шрифта значков там нет, и глиф
        // вышел бы пустым прямоугольником.
        '${entry.name} $_arrow ${entry.reference}',
      );
    }

    final name = entry?.name ?? '-';
    return (TextSpan(text: name), name);
  }

  /// Стрелка для подсказки: набором её рисует глиф шрифта значков.
  static const String _arrow = '→';
}
