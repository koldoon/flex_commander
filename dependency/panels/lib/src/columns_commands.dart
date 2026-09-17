import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'column_chain.dart';
import 'columns_view.dart';

/// Клавиши вида «Столбцы» (`docs/spec/panel-view-columns.md`, §6).
///
/// Свои команды, а не общие «по колонкам»: у тех шаг **постоянный** — в кратком
/// виде столбец это отрезок списка известной длины. Здесь шаг переменный: до
/// родителя может быть сколько угодно строк, внутрь — ровно одна, а до соседа
/// по каталогу — столько, во сколько развернулось лежащее между ними чужое
/// раскрытое поддерево.
///
/// **У края команда не отказывается, а молча стоит.** Откажись она — клавишу
/// подхватит следующая привязка: `Left` свернул бы ветвь, невидимо убив все
/// столбцы справа, а `Home` увёл бы курсор на корень, которого в столбцах не
/// видно вовсе.
abstract class _ColumnsCommand extends AppCommand {
  /// Вид спрашивается вместе с набором строк: столбцы бывают только у
  /// древесных, а древесные — не только у столбцов.
  @override
  bool isExecutable(CommandContext context) =>
      context.session.view == ColumnsView.viewId && context.session.rows.isTree;

  /// Цепочка столбцов на сейчас.
  ///
  /// Считается заново на каждое нажатие, а не берётся у вида: команда живёт в
  /// ядре клавиш и о виджетах не знает — а один проход по строкам дешевле
  /// любого способа их связать.
  ColumnChain chainOf(CommandContext context) => ColumnChain.of(context.session.entries, context.session.cursorIndex);

  /// Курсор ни в одном столбце — он на корне, а корень столбцом не рисуется.
  ///
  /// Нажатие обязано что-то делать, и делает оно самое понятное: заводит
  /// курсор в последний столбец цепочки — тот, в чей каталог смотрит панель.
  /// Случай не выдуманный: курсор мог встать на корень в дереве, а вид
  /// переключили после.
  bool enterChain(CommandContext context, ColumnChain chain) {
    if (chain.current >= 0 || chain.columns.isEmpty) {
      return false;
    }
    final rows = chain.columns.last.rows;
    if (rows.isEmpty) {
      return false;
    }
    context.session.setCursorToPath(context.session.entries[rows.first].path);
    return true;
  }
}

/// Шаг вглубь и обратно: `Right` и `Left`.
class ColumnsStepCommand extends _ColumnsCommand {
  ColumnsStepCommand({required this.deeper});

  static const String inId = 'panel.columns.in';
  static const String outId = 'panel.columns.out';

  /// true — вправо, внутрь; false — влево, к родителю.
  final bool deeper;

  @override
  String get id => deeper ? inId : outId;

  @override
  String get label => deeper ? tr('Into the directory') : tr('Out to the parent');

  @override
  String get description =>
      deeper
          ? tr('Show what is inside and move the cursor there')
          : tr('Move the cursor to the directory this column grew from');

  @override
  Set<String> get keywords => const {'columns', 'finder'};

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final rows = panel.entries;
    final at = panel.cursorIndex;
    if (at < 0 || at >= rows.length) {
      return;
    }
    // Курсор на корне: стрелка заводит его в цепочку, а не пропадает впустую.
    if (enterChain(context, chainOf(context))) {
      return;
    }

    if (!deeper) {
      // **Не сворачивая**: столбец справа остаётся на месте — из него только
      // что вышли, и убирать его нажатием «назад» значило бы стирать пройденное.
      //
      // Корень столбцом не рисуется, и вставать на него некуда: в первом
      // столбце команда молча стоит.
      final parent = _parentOf(rows, at);
      if (parent >= 0 && rows[parent].level >= 1) {
        panel.setCursorToPath(rows[parent].path);
      }
      return;
    }

    final row = rows[at];
    if (!row.isDirectory) {
      return;
    }
    if (!row.isOpen) {
      panel.setExpanded(row.path, expanded: true);
      return;
    }
    // Раскрытая ветвь — шаг внутрь: следующая строка и есть её первый ребёнок.
    // Пустой каталог такой строки не даёт, и курсор остаётся на месте.
    if (at + 1 < rows.length && rows[at + 1].level > row.level) {
      panel.setCursorToPath(rows[at + 1].path);
    }
  }

  /// Строка каталога, в котором лежит строка [at]; -1 — такой нет.
  static int _parentOf(List<FileEntry> rows, int at) {
    for (var i = at - 1; i >= 0; i--) {
      if (rows[i].level < rows[at].level) {
        return i;
      }
    }
    return -1;
  }
}

/// Насколько двигать курсор по столбцу.
enum ColumnsRowStep {
  /// Соседняя строка.
  one,

  /// Страница — столько, сколько видно.
  page,

  /// Край столбца.
  edge,
}

/// Ход курсора **по столбцу**: `Up`/`Down`, `PgUp`/`PgDn`, `Home`/`End`.
///
/// Общие команды сюда не годятся: они считают строки подряд, а между соседями
/// по каталогу может лежать чужое раскрытое поддерево — раскрывали его в
/// дереве, память раскрытого общая. Шаг «одна строка» увёл бы курсор внутрь
/// него, а `Home` — на корень, которого в столбцах не видно.
class ColumnsRowCommand extends _ColumnsCommand {
  ColumnsRowCommand({required this.down, required this.step});

  static const String upId = 'panel.columns.up';
  static const String downId = 'panel.columns.down';
  static const String pageUpId = 'panel.columns.pageUp';
  static const String pageDownId = 'panel.columns.pageDown';
  static const String firstId = 'panel.columns.first';
  static const String lastId = 'panel.columns.last';

  final bool down;
  final ColumnsRowStep step;

  @override
  String get id => switch ((step, down)) {
    (ColumnsRowStep.one, false) => upId,
    (ColumnsRowStep.one, true) => downId,
    (ColumnsRowStep.page, false) => pageUpId,
    (ColumnsRowStep.page, true) => pageDownId,
    (ColumnsRowStep.edge, false) => firstId,
    (ColumnsRowStep.edge, true) => lastId,
  };

  @override
  String get label => switch ((step, down)) {
    (ColumnsRowStep.one, false) => tr('Row above in the column'),
    (ColumnsRowStep.one, true) => tr('Row below in the column'),
    (ColumnsRowStep.page, false) => tr('Column page up'),
    (ColumnsRowStep.page, true) => tr('Column page down'),
    (ColumnsRowStep.edge, false) => tr('First row of the column'),
    (ColumnsRowStep.edge, true) => tr('Last row of the column'),
  };

  @override
  String get description => tr('Move the cursor inside its own column');

  @override
  Set<String> get keywords => const {'columns', 'finder'};

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.session;
    final chain = chainOf(context);
    if (chain.current < 0) {
      enterChain(context, chain);
      return;
    }
    final column = chain.columns[chain.current].rows;
    final place = column.indexOf(panel.cursorIndex);
    if (place < 0) {
      return;
    }

    final moved = switch (step) {
      ColumnsRowStep.one => place + (down ? 1 : -1),
      // Страница — то, что видно: её меряет вид и кладёт в панель, как и для
      // всех прочих видов.
      ColumnsRowStep.page => place + (down ? 1 : -1) * (panel.pageSize - 1).clamp(1, panel.pageSize),
      ColumnsRowStep.edge => down ? column.length - 1 : 0,
    };
    final target = column[moved.clamp(0, column.length - 1)];
    // Путём, а не номером: пока заявка едет, придержка успевает раскрыть
    // каталог под курсором, и номер соседа означает уже первую строку внутри
    // него (`docs/spec/panel-view-columns.md`, §5).
    panel.setCursorToPath(panel.entries[target].path);
  }
}
