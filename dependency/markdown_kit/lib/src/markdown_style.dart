import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'markdown_table_width.dart';

/// Как выглядит свёрстанный markdown: тем же набором стилей, что и окна.
///
/// Своей темы у разметки нет и быть не должно — документ обязан выглядеть как
/// приложение, а не как страница GitHub.
///
/// Жил этот набор в окне обновления (`fc_updater`) и переехал сюда, когда
/// markdown стал показываться в двух местах: две копии оформления разошлись бы
/// молча, и заметил бы это человек, а не сборка
/// (`docs/spec/markdown-viewer.md`, §2).
/// Интерлиньяж абзацев — в долях кегля.
///
/// В окнах подписи короткие, и интерлиньяж у них свой, от шрифта, около 1,15:
/// для документа это слеплено. Ориентиры: «Practical Typography» Баттерика —
/// 120–145 % кегля, стиль markdown GitHub — 1,5. Берём верх диапазона
/// Баттерика, рядом с GitHub (`docs/spec/markdown-viewer.md`, §6).
const double fcMarkdownLineHeight = 1.45;

/// Отбивка между абзацами — в долях кегля: 0,75, как у GitHub (12 при 16), в
/// середине диапазона Баттерика (50–100 % кегля). Просвет между абзацами
/// выходит в два с половиной раза больше просвета между строками — абзац
/// читается абзацем, а не продолжением строки.
const double fcMarkdownParagraphGap = 0.75;

MarkdownStyleSheet fcMarkdownStyle(FcTheme theme) {
  final metrics = theme.metrics;
  // Всё, что стоит в строке абзаца, — одной высоты строки: иначе строка со
  // словом жирным или кодом выходила бы выше соседней. Добавка поровну сверху и
  // снизу, а не по шрифту: так строка стоит посередине своей высоты.
  final body = theme.dialogTextStyle.copyWith(
    height: fcMarkdownLineHeight,
    leadingDistribution: TextLeadingDistribution.even,
  );
  final size = body.fontSize ?? metrics.fontSize;
  final code = body.copyWith(fontFamily: theme.fonts.fixed, fontFamilyFallback: theme.fonts.fixedFallback);

  return MarkdownStyleSheet(
    p: body,
    // Заголовки разделов — тем же кеглем, что заголовки в справке: они
    // разделяют части рассказа, а не спорят с заголовком окна.
    h1: theme.headingStyle.copyWith(fontSize: metrics.sectionHeadingFontSize),
    h2: theme.headingStyle.copyWith(fontSize: metrics.sectionHeadingFontSize),
    h3: theme.headingStyle,
    strong: body.copyWith(fontWeight: FontWeight.bold, color: theme.colors.dialogLabel),
    em: body.copyWith(fontStyle: FontStyle.italic),
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
    a: body.copyWith(color: theme.colors.dialogLabel, decoration: TextDecoration.underline),
    listBullet: body,
    // Зазор от маркера до текста — тот же, что у флажка до его метки
    // (`checkboxGap`): маркер списка и есть знак при подписи. В библиотеке он
    // 4, и текст стоял к точке вплотную; заодно флажок в списке задач теперь
    // отбит от текста ровно так же, как флажок в окне.
    listBulletPadding: EdgeInsets.only(right: metrics.checkboxGap),
    blockSpacing: size * fcMarkdownParagraphGap,
    // Ширина колонок — по содержимому: поровну колонка «Да/Нет» получала
    // столько же, сколько колонка с описанием на три строки.
    tableColumnWidth: const FcContentColumnWidth(),
    tableHead: theme.dialogTextStyle.copyWith(fontWeight: FontWeight.bold, color: theme.colors.dialogLabel),
    tableBody: theme.dialogTextStyle,
    // Читают таблицу слева направо и сверху вниз — так текст в ячейках и
    // стоит. По центру заголовок отрывался бы от своей колонки, а по середине
    // высоты строка с одной строчкой уезжала бы от соседней с тремя.
    tableHeadAlign: TextAlign.left,
    tableVerticalAlignment: TableCellVerticalAlignment.top,
    // Линейки таблицы — тем же цветом, каким панель делит колонки: таблица в
    // документе и таблица файлов рисуют одно и то же, и разными им быть незачем.
    // Углы скруглены тем же радиусом, что у затенённой врезки: оба —
    // «вставленный кусок», и острые углы у одного при скруглённых у другого
    // читаются как небрежность.
    tableBorder: TableBorder.all(
      color: theme.colors.columnDivider,
      width: metrics.strokeWidth,
      borderRadius: BorderRadius.circular(metrics.inputRadius),
    ),
    // Тем же отступом, что и у затенённой врезки: таблица и врезка — оба
    // «вставленный кусок», и внутренние поля у них должны совпадать. С прежним
    // текст стоял вплотную к линейкам.
    tableCellsPadding: EdgeInsets.all(metrics.dialogPadding),
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
