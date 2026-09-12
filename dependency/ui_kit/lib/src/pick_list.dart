import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_scope.dart';

import 'command_dialog.dart';
import 'fc_theme.dart';
import 'palette_search.dart';
import 'text_trim.dart';

/// Строка списка с отбором.
///
/// Три части, и все необязательны, кроме первой: имя, приглушённое уточнение
/// рядом с ним и приглушённое же примечание справа. У палитры это команда,
/// её описание и клавиши; у истории адресов — только адрес.
class FcPickRow {
  const FcPickRow({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.trailing = '',
    this.keywords = const [],
    this.marked = false,
  });

  /// Чем строка отзовётся, когда её выберут.
  final String id;

  final String title;

  /// Уточнение сразу за именем: у палитры — что команда делает.
  ///
  /// Показывается, но **не ищется**: уточнение — это предложение, и поиск по
  /// нему выдавал бы всё сразу на любом общем слове. Для «нашлось не по
  /// названию» есть [keywords].
  final String subtitle;

  /// Справа, приглушённо: клавиши, дата, размер — что угодно, что не спорит с
  /// именем за внимание.
  final String trailing;

  /// Слова, по которым строка находится, но которых в ней не видно: `gz` у
  /// «Mk Tar», название модуля у любой команды палитры. У истории адресов их
  /// нет — там ищут по самому пути.
  final List<String> keywords;

  /// Строка помечена значком слева: «вот эта».
  ///
  /// Не «выбранная» — выбранное показано курсором и меняется стрелками. Это
  /// про **место в списке**: в истории переходов так помечен шаг, на котором
  /// сессия стоит сейчас, и по соседям видно, куда поведут «назад» и «вперёд»
  /// (`docs/spec/session-history.md`, §9).
  final bool marked;
}

/// Сколько строк помещается в обзоре списка; от этого считается шаг
/// `PgUp`/`PgDn`.
///
/// Записка на двоих: заполняет её сам список — высоту ему даёт рама окна, и до
/// первой раскладки её не знает никто, — а читает [FcPickList.moveSelection],
/// которую зовут снаружи, из разбора клавиш. Так же устроен и шаг страницы в
/// панели: число видимых строк выставляет таблица, а пользуется им команда
/// (`panel.pageSize`).
///
/// Вызывающему остаётся одно: завести её и отдать в оба места.
class FcPickPage {
  /// Строк в обзоре; 0 — списка на экране ещё нет.
  int size = 0;
}

/// Список с нечётким отбором, подсветкой совпавшего и ходом стрелками и
/// страницами.
///
/// Общий у палитры команд, истории адресов и окна масок: показ строки, отбор и
/// ход по списку у них одинаковые, и держать это в трёх местах — верный способ
/// разойтись. А вот смысл `Enter` у них разный (запустить против «вписать в
/// поле»), поэтому нажатие список не толкует: он сообщает о выборе, а решает
/// вызывающий.
class FcPickList extends StatefulWidget {
  const FcPickList({
    super.key,
    required this.rows,
    required this.query,
    required this.selected,
    required this.onTap,
    this.emptyMessage,
    this.textInset,
    this.page,
    this.mark = FcPickMark.cursor,
    this.trimHead = false,
    this.dimPathHead = false,
  });

  final List<FcPickRow> rows;

  /// Набранное: по нему отбирают и подсвечивают.
  final String query;

  /// Который выбран; -1 — не выбран никто.
  final int selected;

  final void Function(String id) onTap;

  /// Что сказать, когда показывать нечего; null — «ничего не найдено».
  final String? emptyMessage;

  /// Отступ текста строки от края списка; пусто — как у поля ввода без подписи.
  ///
  /// Задают его там, где поле стоит в столбце значений: текст в нём начинается
  /// за подписью, и список обязан встать под ним, а не под подписью.
  final double? textInset;

  /// Куда сообщать размер страницы. Пусто — `PgUp`/`PgDn` списку не нужны.
  final FcPickPage? page;

  /// Чем показано выбранное.
  final FcPickMark mark;

  /// Обрезать строку **слева**, а не справа.
  ///
  /// Для путей: конец строки важнее — в нём тот каталог, о котором речь, — и
  /// режется так же, как в плашке пути (`trimTextHead`). Обычные списки
  /// (палитра, маски) режут хвост: у команды важнее начало имени.
  final bool trimHead;

  /// В пути ярко набрано **последнее звено**, остальное приглушено.
  ///
  /// Списки путей — история переходов и история адресов — читают по именам
  /// каталогов: куда именно ведёт строка, сказано в её конце, а начало у
  /// соседних строк чаще всего одно и то же. Приглушённое начало перестаёт
  /// спорить с концом за внимание.
  final bool dimPathHead;

  @override
  State<FcPickList> createState() => _FcPickListState();

  /// Отобранное в том порядке, в каком его покажут.
  ///
  /// Статический, потому что тот же порядок нужен и вызывающему: он держит
  /// выбор номером и должен знать, между чем этот номер ходит.
  static List<FcPickRow> filter(List<FcPickRow> rows, String query, {List<String> recent = const []}) {
    final found = <(FcPickRow, PaletteMatch)>[];
    for (final row in rows) {
      final match = matchCommand(query, label: row.title, keywords: row.keywords);
      if (match != null) {
        found.add((row, match));
      }
    }

    found.sort((a, b) {
      final byMatch = a.$2.compareTo(b.$2);
      if (byMatch != 0 && query.trim().isNotEmpty) {
        return byMatch;
      }
      // Недавнее — последний довод при равном весе, а не самостоятельная сила:
      // искали конкретное, а не привычное.
      final left = recent.indexOf(a.$1.id);
      final right = recent.indexOf(b.$1.id);
      if (left != right) {
        return (left < 0 ? recent.length : left).compareTo(right < 0 ? recent.length : right);
      }
      return byMatch != 0 ? byMatch : a.$1.title.compareTo(b.$1.title);
    });

    return [for (final (row, _) in found) row];
  }

  /// Куда переставить выбор по нажатию; null — клавиша не про список.
  ///
  /// Здесь же и правило края: с первой строки вверх — «никуда» (-1), чтобы
  /// вызывающий мог вернуть набранное руками.
  ///
  /// [page] нужна только для `PgUp`/`PgDn`: без неё страница не пройдена и обе
  /// клавиши остаются вызывающему.
  static int? moveSelection(
    KeyEvent event, {
    required int selected,
    required int count,
    bool wrap = true,
    FcPickPage? page,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    final pageDown = page != null && key == LogicalKeyboardKey.pageDown;
    final pageUp = page != null && key == LogicalKeyboardKey.pageUp;
    if (count == 0 || !(down || up || pageDown || pageUp)) {
      return null;
    }

    if (pageDown || pageUp) {
      // Страница — видимые строки минус одна, как в панели: перекрытие в одну
      // строку не даёт потерять место, где остановился взгляд. Пока список не
      // раскладывали, страницы нет — тогда шаг в строку, как у стрелки.
      final step = (page.size - 1).clamp(1, count);
      // Из поля вверх страницей идти некуда: наверху списка ничего не выбрано и
      // так.
      if (pageUp && selected < 0) {
        return null;
      }
      // У края — упор, а не заворот: стрелка по кругу читается как ход, а
      // страница с конца в начало от одного нажатия — как потеря места.
      return (selected + (pageDown ? step : -step)).clamp(0, count - 1);
    }

    final next = selected + (down ? 1 : -1);
    if (next >= count) {
      return wrap ? 0 : count - 1;
    }
    if (next < 0) {
      return wrap ? count - 1 : -1;
    }
    return next;
  }
}

/// Чем показано выбранное в списке.
enum FcPickMark {
  /// Курсором: подсветка во всю ширину, как в панели.
  ///
  /// Годится там, где по списку **ходят** и выбирают: палитра команд, окна
  /// выбора. У таких списков есть во что упереться — поле ввода сверху, рамка
  /// окна по краям.
  cursor,

  /// Начертанием: выбранное набрано жирным и светлым, остальное — приглушённым.
  ///
  /// Для списков, которые не выбирают, а **показывают**, где вы сейчас:
  /// оглавление настроек. Курсор там висел бы в воздухе — ни рамки, ни фона,
  /// обо что ему упереться, у оглавления нет.
  weight,
}

class _FcPickListState extends State<FcPickList> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FcPickList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      // Выбранное держится на виду: перебор стрелками не должен уезжать за
      // край.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSelected());
    }
  }

  /// Сколько строк видно — вызывающему, для шага страницы.
  ///
  /// Меряется после раскладки и по обзору прокрутки, а не `LayoutBuilder`ом:
  /// тот не умеет отвечать на вопрос о собственной ширине — тот самый, который
  /// рама окна задаёт каждому окну (`IntrinsicWidth`).
  void _measurePage() {
    final page = widget.page;
    if (page == null || !mounted) {
      return;
    }
    if (!_scroll.hasClients) {
      page.size = 0;
      return;
    }
    final metrics = FcTheme.of(context).metrics;
    page.size = (_scroll.position.viewportDimension / (metrics.rowHeight + metrics.rowGap)).floor();
  }

  void _showSelected() {
    if (!_scroll.hasClients || widget.selected < 0) {
      return;
    }
    final metrics = FcTheme.of(context).metrics;
    final line = metrics.rowHeight + metrics.rowGap;
    final top = widget.selected * line;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + line > position.pixels + position.viewportDimension) {
      _scroll.jumpTo((top + line - position.viewportDimension).clamp(0, position.maxScrollExtent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final metrics = theme.metrics;

    if (widget.page != null) {
      // Обзор известен только после раскладки: до неё у прокрутки нет ни
      // высоты, ни самой позиции.
      WidgetsBinding.instance.addPostFrameCallback((_) => _measurePage());
    }

    if (widget.rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: metrics.dialogPadding),
        child: Text(
          widget.emptyMessage ?? context.strings.tr('Nothing found'),
          textAlign: TextAlign.center,
          style: theme.dialogLabelStyle,
        ),
      );
    }

    return SingleChildScrollView(
      // Не ленивый список: рама окна меряет содержимое (`IntrinsicWidth`), а
      // ленивый на такой вопрос отвечать не умеет.
      controller: _scroll,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.rows.length; i++) _row(context, theme, widget.rows[i], i == widget.selected),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, FcTheme theme, FcPickRow row, bool current) {
    final colors = theme.colors;
    final metrics = theme.metrics;
    // Яркое — имя, приглушённое — уточнение и примечание.
    //
    // Роли легко перепутать местами: в теме по умолчанию `dialogLabel` белый, а
    // `dialogText` — приглушённый синий.
    final base = TextStyle(fontFamily: theme.fonts.ui, fontSize: metrics.fontSize);
    final byWeight = widget.mark == FcPickMark.weight;
    final bright =
        byWeight
            // Выбранное отличается только набором: светлое и жирное против
            // приглушённого. Тот же приглушённый цвет, каким набран список
            // файлов, — роль здесь своя (`dialogText`), а значение общее.
            ? base.copyWith(
              color: current ? colors.dialogLabel : colors.dialogText,
              fontWeight: current ? FontWeight.bold : null,
            )
            : base.copyWith(color: current ? colors.cursorText : colors.dialogLabel);
    final dim = base.copyWith(color: colors.dialogText);
    final match = matchCommand(widget.query, label: row.title);

    // Приглушённое начало пути. На строке под курсором — не общий
    // приглушённый цвет (он набран для тёмного фона окна и на подсветке
    // тонет), а тот же светлый, приспущенный к её фону.
    final dimPath =
        current && !byWeight
            ? bright.copyWith(color: Color.lerp(bright.color, colors.cursorBackground, 0.45))
            : bright.copyWith(color: colors.dialogText);

    /// Путь двумя цветами: последнее звено ярко, всё до него — приглушённо.
    ///
    /// Подсветка совпавшего делится между половинами: буквы запроса могут
    /// попасть и туда, и сюда.
    List<TextSpan> pathSpans(String text, List<int> hits) {
      final cut = text.lastIndexOf('/');
      // Строку с хвостовым разделителем делить не на что: последнего звена у
      // неё нет вовсе. Такие приходят из старых настроек — показываем их так
      // же, как пишем нынешние (`pathWithoutTrailingSlash`).
      if (widget.dimPathHead && cut == text.length - 1 && text.length > 1) {
        return pathSpans(text.substring(0, text.length - 1), [
          for (final hit in hits)
            if (hit < text.length - 1) hit,
        ]);
      }
      if (!widget.dimPathHead || cut < 0 || cut == text.length - 1) {
        return highlightMatch(text, hits, bright);
      }
      return [
        ...highlightMatch(text.substring(0, cut + 1), [
          for (final hit in hits)
            if (hit <= cut) hit,
        ], dimPath),
        ...highlightMatch(text.substring(cut + 1), [
          for (final hit in hits)
            if (hit > cut) hit - cut - 1,
        ], bright),
      ];
    }

    /// Заголовок строки: подсвеченный, а если надо — обрезанный с головы.
    ///
    /// Обрезка идёт по **доступной** ширине, поэтому меряется в раскладке:
    /// сколько её осталось, знает только `LayoutBuilder`. Он тут безопасен —
    /// окна со списками задают себе ширину сами (`DialogSpec.ownWidth`), и
    /// про интринсики их никто не спрашивает.
    Widget title(List<TextSpan> spans) =>
        Text.rich(TextSpan(children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);

    final inset = widget.textInset ?? dialogInputTextInset(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(row.id),
      child: Container(
        height: metrics.rowHeight + metrics.rowGap,
        color: current && !byWeight ? colors.cursorBackground : null,
        // Подсветка — во всю ширину, отбит только текст: строка выбора обязана
        // доходить до краёв, иначе читается не как «эта строка», а как «эта
        // плитка». А текст стоит ровно под набранным в поле.
        alignment: Alignment.centerLeft,
        child: Stack(
          children: [
            // Значок стоит **в поле слева**, а не в колонке перед текстом:
            // колонка сдвинула бы строки вправо, и список перестал бы стоять
            // под полем ввода. В поле он и помещается — его там ровно столько,
            // сколько отбит текст (`docs/spec/session-history.md`, §9).
            if (row.marked)
              Positioned(
                left: ((inset - metrics.fontSize) / 2).clamp(0, inset),
                top: 0,
                bottom: 0,
                child: Center(child: Icon(theme.icons.angleRight, size: metrics.fontSize, color: bright.color)),
              ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child:
                          widget.trimHead
                              ? LayoutBuilder(
                                builder: (context, constraints) {
                                  final scaler = MediaQuery.textScalerOf(context);
                                  final shown = trimTextHead(row.title, bright, constraints.maxWidth, scaler);
                                  // Подсветка считается по целой строке, а
                                  // показывают обрезанную: совпавшие буквы,
                                  // ушедшие с головой, отпадают, оставшиеся
                                  // сдвигаются на отрезанное.
                                  final cut = row.title.length - shown.length + (shown.startsWith('…') ? 1 : 0);
                                  final hits = <int>[
                                    for (final hit in match?.labelHits ?? const <int>[])
                                      if (hit >= cut) hit - cut + (shown.startsWith('…') ? 1 : 0),
                                  ];
                                  return title(pathSpans(shown, hits));
                                },
                              )
                              : title([
                                ...pathSpans(row.title, match?.labelHits ?? const []),
                                // Уточнение без подсветки: по нему не ищут, и
                                // подсвечивать в нём нечего.
                                if (row.subtitle.isNotEmpty) TextSpan(text: '   ${row.subtitle}', style: dim),
                              ]),
                    ),
                    if (row.trailing.isNotEmpty) ...[
                      SizedBox(width: metrics.columnGap),
                      Text(
                        row.trailing,
                        style: dim.copyWith(
                          fontFamily: theme.fonts.fixed,
                          fontFamilyFallback: theme.fonts.fixedFallback,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Совпавшие буквы — жирным.
///
/// Без подсветки непонятно, почему строка нашлась: `cpf` в `Copy File` со
/// стороны выглядит случайностью.
///
/// [matched] — чем выделять, если жирным нельзя: в окне настроек имя настройки
/// и так набрано жирным, и выделять его тем же нечем.
List<TextSpan> highlightMatch(String text, List<int> hits, TextStyle style, {TextStyle? matched}) {
  if (hits.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }
  final mark = matched ?? style.copyWith(fontWeight: FontWeight.bold);

  final spans = <TextSpan>[];
  final marked = hits.toSet();
  final buffer = StringBuffer();
  var bold = marked.contains(0);

  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString(), style: bold ? mark : style));
      buffer.clear();
    }
  }

  for (var i = 0; i < text.length; i++) {
    final now = marked.contains(i);
    if (now != bold) {
      flush();
      bold = now;
    }
    buffer.write(text[i]);
  }
  flush();

  return spans;
}
