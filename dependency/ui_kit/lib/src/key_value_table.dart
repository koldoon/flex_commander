import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'command_dialog.dart';
import 'dialog_body.dart';
import 'fc_theme.dart';

/// Строка таблицы: название и одно или два значения.
///
/// Третья ячейка нужна там, где значению нужно пояснение — команде, например,
/// нужны и клавиши, и описание. Где её нет, пустой столбец не остаётся:
/// у раздела столько столбцов, сколько ему нужно.
class FcTableRow {
  const FcTableRow(this.name, this.value, [this.note = '']);

  final String name;
  final String value;
  final String note;

  List<String> get cells => note.isEmpty ? [name, value] : [name, value, note];
}

/// Раздел таблицы — заголовок и строки под ним.
class FcTableSection {
  const FcTableSection(this.title, this.rows);

  final String title;
  final List<FcTableRow> rows;

  /// Сколько столбцов нужно разделу: по самой полной строке.
  int get columns => rows.fold(1, (count, row) => row.cells.length > count ? row.cells.length : count);
}

/// Разделы «ключ → значение» — без рамы и без кнопок.
///
/// Отдельно от [FcKeyValueTable] потому, что мест у этой разметки два: окно
/// команды (там снизу кнопки) и область панели, где показывают сведения об
/// объекте (там кнопок нет вовсе). Разметка при этом обязана быть одна: два
/// показа одного и того же однажды разойдутся.
///
/// Прокручивается сама: стрелками, PgUp/PgDn, Home/End, — а Enter и Esc
/// отдаёт тому, кто её показывает.
class FcKeyValueSections extends StatefulWidget {
  const FcKeyValueSections({
    super.key,
    required this.sections,
    this.autofocus = true,
    this.padded = true,
    this.horizontal = false,
    this.divided = false,
    this.bounded = false,
    this.padding,
  });

  /// Доли ширины у подписи и у значения: `2 : 3`.
  ///
  /// Не поровну: подпись — короткое название поля, значение бывает путём,
  /// адресом или расширенным атрибутом, и место ему нужнее.
  static const int labelShare = 2;
  static const int valueShare = 3;

  final List<FcTableSection> sections;

  /// Забирать ли фокус: в окне — да, листать её приходится сразу; в панели —
  /// нет, там ввод принадлежит списку файлов.
  final bool autofocus;

  /// Отступы содержимого окна. В панели у рамы свои.
  final bool padded;

  /// Листается ли таблица **вбок**.
  ///
  /// Нужно там, где значение бывает одним длинным словом без пробелов:
  /// расширенный атрибут (`0083;68b8ab13;Safari;C6460336-…`), путь, адрес. Их
  /// перенос разорвать не может, и без прокрутки они уходят за раму — в узкой
  /// панели быстрого просмотра это видно сразу.
  ///
  /// По умолчанию нет: справке и настройкам перенос как раз и нужен — там
  /// значения из обычных слов, и лента вбок читалась бы хуже столбца.
  final bool horizontal;

  /// Отделять строки друг от друга линейкой.
  ///
  /// Нужно там, где последний столбец **переносится**: описания команд в
  /// справке занимают то одну строчку, то три, и без линейки соседние
  /// описания читаются одним сплошным абзацем — не видно, где кончается одно
  /// и начинается другое.
  ///
  /// По умолчанию нет: в окне сведений значения однострочные, и линейки там
  /// были бы решёткой на ровном месте.
  final bool divided;

  /// Поля содержимого — свои, вместо [padded].
  ///
  /// Лежат они **внутри** прокрутки, а не вокруг неё: так содержимое уезжает
  /// под плашку пути целиком, а не обрезается по её нижнему краю. Тем же
  /// приёмом живёт панель со сплошным содержимым — картинка занимает всю раму,
  /// а плашка лежит поверх (`FcPanelFrame.fillsFrame`).
  final EdgeInsetsGeometry? padding;

  /// Ширина задана снаружи: столбцы делят её долями, а текст переносится.
  ///
  /// Так таблица живёт **в панели**, где ширина известна заранее и меняется
  /// вместе с окном. Столбцы берут [labelShare] и [valueShare], длинное
  /// значение переносится по краю столбца — включая слово без пробелов:
  /// его каркас разрывает сам, по знакам.
  ///
  /// В окне так нельзя: рама меряет содержимое интринсиками, а доля в таком
  /// замере отвечает нулём — окно вышло бы шириной с заголовок
  /// (`docs/spec/dialog-body.md`). Там столбцы по-прежнему меряются по себе.
  final bool bounded;

  @override
  State<FcKeyValueSections> createState() => _FcKeyValueSectionsState();
}

class _FcKeyValueSectionsState extends State<FcKeyValueSections> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Таблицу листают клавишами: её читают, а не заполняют.
  ///
  /// Enter и Esc сюда не попадают — они не наши; их обработает рама, когда
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
      LogicalKeyboardKey.home => 0.0,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) {
      return KeyEventResult.ignored;
    }
    _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = FcTheme.of(context).metrics;
    final columns = keyValueColumns(widget.sections);
    final widths = keyValueColumnWidths(context, widget.sections, columns: columns, bounded: widget.bounded);

    return Focus(
      autofocus: widget.autofocus,
      canRequestFocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: widget.padding ?? (widget.padded ? dialogContentPadding(context) : EdgeInsets.zero),
        child: _sideways(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.sections.length; i++) ...[
                // Между плашками — то же поле, что у окна по бокам: раздел
                // отбит от раздела ровно так же, как содержимое от края, и
                // окно читается одной сеткой. Разделы без плашек стоят как
                // стояли: там просвет отделяет заголовок от чужих строк, а не
                // блок от блока.
                if (i > 0) SizedBox(height: widget.divided ? metrics.dialogHorizontalPadding : metrics.sectionGap),
                FcKeyValueSection(
                  section: widget.sections[i],
                  widths: widths,
                  columns: columns,
                  divided: widget.divided,
                  bounded: widget.bounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Обёртка для прокрутки вбок; без неё — то же самое, что дали.
  ///
  /// Внутри вертикальной, а не снаружи: листают её сверху вниз, и заголовок
  /// раздела должен уезжать вместе со своими строками, а не оставаться на
  /// месте, пока строки едут вбок.
  Widget _sideways(Widget child) =>
      widget.horizontal ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: child) : child;
}

/// Сколько столбцов нужно разделам — по самому полному из них.
int keyValueColumns(List<FcTableSection> sections) =>
    sections.fold(1, (count, section) => section.columns > count ? section.columns : count);

/// Ширины столбцов, кроме последнего, — **по всем разделам сразу**.
///
/// Одна таблица, а не таблица на раздел: подписи разных разделов описывают
/// один и тот же объект, и стоять они обязаны на одной глубине. Последний
/// столбец здесь не меряется — ему достаётся весь остаток, и переносится он
/// по краю окна, а не раньше.
///
/// Считается по **всем** разделам, даже когда показаны не все: в справке с
/// поиском столбцы иначе прыгали бы на каждую букву
/// (`docs/spec/help-window.md`, §6).
List<double> keyValueColumnWidths(
  BuildContext context,
  List<FcTableSection> sections, {
  required int columns,
  bool bounded = false,
}) {
  // Доли мерить незачем: ширину столбцам задаёт не текст, а отведённое место.
  if (bounded) {
    return List<double>.filled(columns, 0);
  }

  final theme = FcTheme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final widths = List<double>.filled(columns, 0);

  // Тем же стилем, каким ячейки будут набраны: `Text` смешивает переданный
  // стиль с наследуемым, и замер без этого выходит уже нарисованного
  // ([FcTheme.effective]).
  final labelStyle = FcTheme.effective(context, theme.dialogLabelStyle);
  final textStyle = FcTheme.effective(context, theme.dialogTextStyle);

  for (final section in sections) {
    for (final row in section.rows) {
      final cells = row.cells;
      for (var i = 0; i < cells.length && i < columns - 1; i++) {
        final painter = TextPainter(
          text: TextSpan(text: cells[i], style: i == 0 ? labelStyle : textStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width > theme.metrics.helpCellMaxWidth ? theme.metrics.helpCellMaxWidth : painter.width;
        if (width > widths[i]) {
          widths[i] = width;
        }
        painter.dispose();
      }
    }
  }
  return widths;
}

/// Один раздел таблицы «ключ → значение».
///
/// Отдельным виджетом, потому что разделы показывают не только лентой: справка
/// раскладывает их по оглавлению и отбирает поиском, а ширины столбцов у них
/// при этом общие (`docs/spec/help-window.md`, §6).
class FcKeyValueSection extends StatelessWidget {
  const FcKeyValueSection({
    super.key,
    required this.section,
    required this.widths,
    required this.columns,
    this.divided = false,
    this.bounded = false,
    this.shares,
  });

  final FcTableSection section;

  /// Ширины столбцов, общие на все разделы ([keyValueColumnWidths]).
  final List<double> widths;

  final int columns;

  /// Отделять строки друг от друга линейкой — см. [FcKeyValueSections.divided].
  final bool divided;

  /// Ширина задана снаружи — см. [FcKeyValueSections.bounded].
  final bool bounded;

  /// Доли столбцов, когда ширина задана снаружи; null — обычные
  /// [FcKeyValueSections.labelShare] и [FcKeyValueSections.valueShare].
  ///
  /// Задаёт их тот, кто знает, что в столбцах: у справки это имя команды,
  /// клавиши и описание, и делить остаток поровну между последними двумя
  /// неправильно — описание длиннее клавиш в разы.
  final List<int>? shares;

  @override
  Widget build(BuildContext context) => _section(FcTheme.of(context), section, widths, columns);

  /// Раздел целиком: заголовок и строки под ним.
  ///
  /// У таблицы с линейками раздел взят в плашку — ту же, какой обведён список
  /// находок: скругление панели, свой фон и обводка (`dialogListBackground`,
  /// `dialogListBorder`). Так разделы читаются блоками, а не сплошной лентой, —
  /// а строчные линейки внутри отделяют описания друг от друга.
  ///
  /// Без линеек плашки нет: в окне сведений разделы короткие и однострочные,
  /// обводить там нечего.
  Widget _section(FcTheme theme, FcTableSection section, List<double> widths, int columns) {
    final metrics = theme.metrics;
    final title = Text(section.title, style: theme.dialogTitleStyle.copyWith(fontSize: metrics.sectionHeadingFontSize));

    if (!divided) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок раздела — строкой во всю ширину: столбцы под ним те же,
          // что и у соседних разделов. И крупнее подписей, а не только жирнее:
          // разделов много, и на общем кегле заголовок теряется среди них — то
          // же решение, что в окне настроек.
          Padding(padding: EdgeInsets.only(bottom: metrics.sectionEntryGap), child: title),
          _rows(theme, section, widths, columns),
        ],
      );
    }

    return Container(
      width: double.infinity,
      // Поле со всех сторон одинаковое: содержимое не должно прилипать ни к
      // краю плашки, ни к её скруглению.
      padding: EdgeInsets.all(metrics.dialogPadding),
      decoration: BoxDecoration(
        color: theme.colors.dialogListBackground,
        border: Border.all(color: theme.colors.dialogListBorder, width: metrics.strokeWidth),
        borderRadius: BorderRadius.circular(metrics.panelRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(bottom: metrics.sectionEntryGap), child: title),
          _rows(theme, section, widths, columns),
        ],
      ),
    );
  }

  /// Строки раздела — таблицей с **общими** ширинами столбцов.
  ///
  /// Таблица на раздел, а ширины общие: со стороны это и есть одна таблица, у
  /// которой заголовки разделов идут во всю ширину. Собственный `Row` с
  /// `Expanded` тут не годится — рама окна меряет содержимое (`IntrinsicWidth`),
  /// а `Expanded` в такой замер не укладывается и переполняет строку.
  /// Линейка таблицы: та же, что делит колонки списка.
  BorderSide _divider(FcTheme theme) => BorderSide(color: theme.colors.columnDivider, width: theme.metrics.strokeWidth);

  Widget _rows(FcTheme theme, FcTableSection section, List<double> widths, int columns) {
    final metrics = theme.metrics;
    // Просвет вокруг линейки: половина сверху, половина снизу — иначе строка
    // прилипает к той, что над ней. Линейке нужно больше воздуха, чем строке
    // без неё, поэтому и роль другая; без линейки просвет прежний — окна
    // сведений от этой правки поехать не должны.
    final gap = divided ? metrics.dialogLineGap : metrics.dialogPadding / 4;

    return Table(
      // Линейки между строками, а также сверху и снизу: раздел получает
      // видимые края, и таблица перестаёт висеть в пустоте. По бокам линеек
      // нет — столбцы разделены просветом, и вертикальные сделали бы решётку.
      // Только между строками: края раздела рисует плашка вокруг него, и
      // линейка по её кромке была бы второй границей на том же месте.
      border: divided ? TableBorder(horizontalInside: _divider(theme)) : null,
      columnWidths: {
        if (bounded)
          // Долями: подпись и значение делят отведённую ширину, а не растут по
          // содержимому. Столбцов бывает и три — тогда доля значения делится
          // между ними поровну, если не сказано иначе.
          for (var i = 0; i < columns; i++)
            i: FlexColumnWidth(
              shares != null && shares!.length == columns
                  ? shares![i].toDouble()
                  : (i == 0 ? FcKeyValueSections.labelShare.toDouble() : FcKeyValueSections.valueShare / (columns - 1)),
            )
        else ...{
          for (var i = 0; i < columns - 1; i++) i: FixedColumnWidth(widths[i] + metrics.dialogGap),
          // Последний столбец меряется по себе **и** забирает остаток.
          //
          // Оба разом: по себе — чтобы окно выросло под длинное значение (рама
          // облегает содержимое, а `FlexColumnWidth` в замере отвечает нулём и
          // ширины окну не прибавляет); остаток — чтобы на широком окне значение
          // занимало всё место, а не половину.
          columns - 1: const IntrinsicColumnWidth(flex: 1),
        },
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final row in section.rows)
          TableRow(
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  // Просвет между столбцами: ширину им задаёт доля, и без поля
                  // подпись прилипла бы к значению.
                  padding: EdgeInsets.only(
                    top: divided ? gap : 0,
                    bottom: gap,
                    right: bounded && i < columns - 1 ? metrics.dialogGap : 0,
                  ),
                  child: Text(
                    i < row.cells.length ? row.cells[i] : '',
                    style: i == 0 ? theme.dialogLabelStyle : theme.dialogTextStyle,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Таблица «ключ → значение» в окне команды: разделы, строки и одна кнопка.
///
/// Ею показывают справку, настройки, свойства объекта — всё, что укладывается
/// в пары «название — значение». Прокручивается сама: стрелками, PgUp/PgDn,
/// Home/End, — а Enter и Esc отдаёт раме окна.
///
/// Размер задаёт себе само: не больше окна приложения с полями по
/// [FcMetrics.dialogScreenInset] от каждого края. Рамка окна ширину не
/// назначает — она облегает то, что ей дали, — а высоту не ограничивает вовсе,
/// поэтому длинная таблица без этого вылезла бы за экран.
class FcKeyValueTable extends StatefulWidget {
  const FcKeyValueTable({
    super.key,
    required this.sections,
    this.actions = const [],
    this.horizontal = false,
    this.divided = false,
  });

  final List<FcTableSection> sections;

  /// Кнопки окна: у справки и сведений их нет, у окна ошибки — «Report».
  ///
  /// Ряд кнопок собирается здесь, а не у вызывающего: он один на все окна
  /// приложения, и обходить его своей разметкой нельзя (см. ниже). Кнопок нет
  /// вовсе — ряда нет, и места он не занимает: содержимое получает всю высоту
  /// окна (`docs/spec/dialog-body.md`).
  final List<Widget> actions;

  /// Листается ли таблица вбок — см. [FcKeyValueSections.horizontal].
  final bool horizontal;

  /// Отделять ли строки линейкой — см. [FcKeyValueSections.divided].
  final bool divided;

  @override
  State<FcKeyValueTable> createState() => _FcKeyValueTableState();
}

class _FcKeyValueTableState extends State<FcKeyValueTable> {
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      // Не `SizedBox`: ширину окну задаёт содержимое, а это только предел.
      // Рама измеряет содержимое (`IntrinsicWidth`) и облегает его, поэтому
      // короткая таблица даёт узкое окно, а длинная упирается в поля.
      constraints: dialogContentLimits(context),
      child: SizedBox(
        // Ширина берётся у самого широкого раздела: строки внутри растягиваются
        // на всё, что им дали, и сами по себе ничего не требуют.
        width: double.infinity,
        // Тело окна: содержимое, под ним ряд кнопок, прибитый к низу
        // (`docs/spec/dialog-body.md`). Своей разметкой его обходить нельзя —
        // `FcButton` под ограниченной шириной растягивается во всю её ширину,
        // а растянутое окно оставило бы кнопки посреди себя.
        child: FcDialogBody(
          // Листает себя таблица сама — стрелками и PgUp/PgDn, своим
          // контроллером; поля она ставит внутри этой прокрутки.
          scrolls: false,
          insets: FcDialogInsets.none,
          // Своей кнопки «Close» здесь нет: закрывают окно `Esc` и крестик в
          // полосе заголовка, а ряд ради одного слова отнимал бы у содержимого
          // полосу высоты. Кнопки, которые **делают дело**, остаются.
          actions: widget.actions,
          child: FcKeyValueSections(sections: widget.sections, horizontal: widget.horizontal, divided: widget.divided),
        ),
      ),
    );
  }
}
