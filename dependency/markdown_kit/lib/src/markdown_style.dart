import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Как выглядит свёрстанный markdown: тем же набором стилей, что и окна.
///
/// Своей темы у разметки нет и быть не должно — документ обязан выглядеть как
/// приложение, а не как страница GitHub.
///
/// Жил этот набор в окне обновления (`fc_updater`) и переехал сюда, когда
/// markdown стал показываться в двух местах: две копии оформления разошлись бы
/// молча, и заметил бы это человек, а не сборка
/// (`docs/spec/markdown-viewer.md`, §2).
MarkdownStyleSheet fcMarkdownStyle(FcTheme theme) {
  final metrics = theme.metrics;
  final code = theme.dialogTextStyle.copyWith(
    fontFamily: theme.fonts.fixed,
    fontFamilyFallback: theme.fonts.fixedFallback,
  );

  return MarkdownStyleSheet(
    p: theme.dialogTextStyle,
    // Заголовки разделов — тем же кеглем, что заголовки в справке: они
    // разделяют части рассказа, а не спорят с заголовком окна.
    h1: theme.dialogTitleStyle.copyWith(fontSize: metrics.sectionHeadingFontSize),
    h2: theme.dialogTitleStyle.copyWith(fontSize: metrics.sectionHeadingFontSize),
    h3: theme.dialogTitleStyle,
    strong: theme.dialogTextStyle.copyWith(fontWeight: FontWeight.bold, color: theme.colors.dialogLabel),
    em: theme.dialogTextStyle.copyWith(fontStyle: FontStyle.italic),
    code: code,
    // Врезку рисует не библиотека, а `FcCodeBlock`: тег `pre` она заворачивает
    // в рамку **безусловно**, даже когда блок отрисован своим builder'ом
    // (`builder.dart:476-481`), — и диаграмма получила бы рамку от врезки кода.
    // Обходить это нечем, поэтому рамка здесь обезоружена, а рисуется там, где
    // про содержимое врезки уже известно (`markdown-viewer.md`, §4).
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    // Подчёркиванием, а не только цветом: ссылка обязана отличаться от
    // выделенного слова с первого взгляда — иначе по ней просто не нажмут.
    a: theme.dialogTextStyle.copyWith(color: theme.colors.dialogLabel, decoration: TextDecoration.underline),
    listBullet: theme.dialogTextStyle,
    blockSpacing: metrics.dialogGap,
    tableHead: theme.dialogTextStyle.copyWith(fontWeight: FontWeight.bold, color: theme.colors.dialogLabel),
    tableBody: theme.dialogTextStyle,
    // Линейки таблицы — тем же цветом, каким панель делит колонки: таблица в
    // документе и таблица файлов рисуют одно и то же, и разными им быть незачем.
    tableBorder: TableBorder.all(color: theme.colors.columnDivider, width: metrics.strokeWidth),
    tableCellsPadding: EdgeInsets.symmetric(horizontal: metrics.cellPadding, vertical: metrics.dialogLineGap),
    blockquoteDecoration: BoxDecoration(
      color: theme.colors.dialogListBackground,
      borderRadius: BorderRadius.circular(metrics.inputRadius),
    ),
    blockquotePadding: EdgeInsets.all(metrics.dialogPadding),
  );
}

/// Оформление врезки кода: то, что раньше рисовала библиотека по
/// `codeblockDecoration`.
///
/// Вынесено отдельно, чтобы врезка выглядела одинаково и там, где её рисуем мы,
/// и там, где показывается причина отказа рисовальщика.
BoxDecoration fcCodeBlockDecoration(FcTheme theme) => BoxDecoration(
  color: theme.colors.dialogListBackground,
  borderRadius: BorderRadius.circular(theme.metrics.inputRadius),
);
