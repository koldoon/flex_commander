import 'package:flutter/material.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'panels_settings.dart';

/// Строка состояния под списком.
///
/// Что показывается, по убыванию приоритета: текст, выставленный командой →
/// сводка по помеченным объектам → сведения об объекте под курсором.
/// Правила взяты из `getSelectionInfoText` референса.
class PanelStatusBar extends StatelessWidget {
  const PanelStatusBar({super.key, required this.panel, required this.settings});

  final Session panel;

  /// Настройки видов: сколько строчек позволено полосе и чем жертвовать в
  /// длинном имени (`docs/spec/panel-status-lines.md`).
  final PanelsSettings Function() settings;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      // Вместе с панелью — настройки: число строчек правят в окне настроек, и
      // видно это должно быть сразу.
      listenable: Listenable.merge([panel, settings()]),
      builder: (context, _) {
        final error = panel.phase == PanelPhase.error;
        final stroke = theme.metrics.strokeWidth;

        // Высота не задана, а **не меньше**: длинное имя строка договаривает,
        // вырастая на вторую и третью строчку (`docs/widgets.md`, раздел `PanelStatusBar`).
        // Пока текст в одну строку — всё ровно так же, как было.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Линейка не доходит до рамки панели — ровно на её толщину, как в
            // референсе. Дойди она до края, получился бы угол, и полоса
            // читалась бы отдельной коробкой, а не низом той же панели.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: stroke),
              child: SizedBox(height: stroke, child: ColoredBox(color: theme.colors.columnDivider)),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: theme.metrics.statusBarHeight - stroke),
              child: Container(
                // Поле слева и справа: рамка полосы и текст не должны
                // сходиться вплотную. Ролями, а не числом, — иначе отступ
                // останется прежним при любом масштабе темы, а всё вокруг
                // него уедет (`DefaultMetrics(scale: 0.8)` — это «крупная»
                // тема).
                //
                // Сверху и снизу — **ровно то поле**, которое однострочной
                // полосе давала её собственная высота. Пока строка была одна,
                // его создавало выравнивание по середине; выросши, текст упёрся
                // бы в линейку и в рамку.
                padding: EdgeInsets.symmetric(
                  horizontal: theme.metrics.labelPadding + theme.metrics.cellPadding,
                  vertical: _verticalPadding(context, theme),
                ),
                alignment: Alignment.centerLeft,
                child: _text(context, theme, error: error),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Поле над текстом и под ним — то же, что было у однострочной полосы.
  ///
  /// Считается, а не берётся ролью: в однострочном случае его создавала высота
  /// полосы за вычетом самой строки, и назначить сюда любое другое число
  /// значило бы сдвинуть полосу там, где она не менялась.
  double _verticalPadding(BuildContext context, FcTheme theme) {
    final line = textLineHeight(FcTheme.effective(context, theme.statusStyle), MediaQuery.textScalerOf(context));
    final free = theme.metrics.statusBarHeight - theme.metrics.strokeWidth - line;
    return free > 0 ? free / 2 : 0;
  }

  /// Строка состояния: растёт до разрешённого настройкой, дальше договаривает
  /// подсказкой.
  ///
  /// Сюда смотрят, когда имя в списке обрезано, — и обрезанная строка
  /// состояния оставляла бы вопрос без ответа совсем (`docs/spec/tooltips.md`,
  /// §7). `FcTrimmedText` не встаёт: текст набран кусками разных стилей.
  Widget _text(BuildContext context, FcTheme theme, {required bool error}) {
    final style = error ? theme.statusStyle.copyWith(color: theme.colors.error) : theme.statusStyle;
    final view = settings();
    final lines = view.statusLines;
    final (pieces, whole) = _content(theme, context.strings);

    // Своей раскладкой: полоса занимает всю ширину панели, и знать её заранее
    // неоткуда. Интринсиками панель никто не меряет — это не окно команды.
    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = FcTheme.effective(context, style);
        final scaler = MediaQuery.textScalerOf(context);
        final fits = spanFitsLines(_span(measured, pieces), constraints.maxWidth, scaler, maxLines: lines);

        // Хвост режет сам каркас; середину считаем сами — тем же правилом, что
        // и колонки списка, и по кускам, чтобы стрелка ссылки осталась
        // стрелкой (`docs/spec/panel-status-lines.md`, §3).
        final shownPieces =
            fits || !view.trimsNameInMiddle
                ? pieces
                : trimPiecesMiddle(pieces, measured, constraints.maxWidth, scaler, maxLines: lines);

        final shown = Text.rich(
          _span(style, shownPieces),
          maxLines: lines,
          overflow: view.trimsNameInMiddle ? TextOverflow.clip : TextOverflow.ellipsis,
          style: style,
        );
        return fcTooltipIf(context, trimmed: !fits, message: whole, child: shown);
      },
    );
  }

  /// Куски — одним набором.
  InlineSpan _span(TextStyle style, List<TextPiece> pieces) =>
      TextSpan(style: style, children: [for (final piece in pieces) TextSpan(text: piece.$1, style: piece.$2)]);

  /// Что сказано — набором и теми же словами простым текстом.
  ///
  /// Двумя значениями сразу, а не двумя методами: подсказка обязана говорить
  /// **то же**, что полоса, а два места, собирающие одно, однажды разойдутся.
  (List<TextPiece>, String) _content(FcTheme theme, Strings strings) {
    final status = panel.statusText;
    if (status != null && status.isNotEmpty) {
      return ([(status, null, false)], status);
    }

    final marked = panel.markedPaths;
    if (marked.isNotEmpty) {
      final size = panel.markedSize;
      final items = strings.plural(marked.length, one: 'Selected {n} item', other: 'Selected {n} items');
      // Каталоги обходятся фоном, и пока обход идёт, сумма неполная —
      // сказать об этом надо прямо, иначе растущее число выглядит ошибкой.
      final scanning = panel.markedSizeIsFinal ? '' : ' ${strings.tr('(Scanning…)')}';
      final text = size > 0 ? '$items, ${formatBytesLong(size)}$scanning' : '$items$scanning';
      return ([(text, null, false)], text);
    }

    final entry = panel.currentEntry;
    if (entry != null && entry.isLink) {
      // Стрелка — глиф шрифта иконок, а не пара знаков «->»: рисованная
      // стрелка не рассыпается на разные шрифты и выглядит как стрелка.
      return (
        [
          (entry.name, null, false),
          // Стрелка не режется: без неё строка читается как одно длинное имя,
          // а не как ссылка (`docs/spec/panel-status-lines.md`, §3).
          (' ${theme.icons.glyph(theme.icons.angleRight)} ', TextStyle(fontFamily: theme.icons.fontFamily), true),
          (entry.reference, null, false),
        ],
        // В подсказке стрелка — обычный знак: шрифта значков там нет, и глиф
        // вышел бы пустым прямоугольником.
        '${entry.name} $_arrow ${entry.reference}',
      );
    }

    final name = entry?.name ?? '-';
    return ([(name, null, false)], name);
  }

  /// Стрелка для подсказки: набором её рисует глиф шрифта значков.
  static const String _arrow = '→';
}
