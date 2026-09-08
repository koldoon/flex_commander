import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_table.dart';
import 'panels_settings.dart';
import 'tree_view.dart';

/// Дерево и содержимое рядом, в одной стороне.
///
/// Спецификация — `docs/spec/panel-view-combined.md`.
///
/// **Столбцы — это две сессии панели** в одном слоте (`panel-slots.md`): слева
/// ветви одних каталогов, справа обычный список того каталога, на котором стоит
/// курсор дерева. Курсор один и стоит в той сессии, которую слот показывает, —
/// поэтому ни одна команда об этом виде не знает: `Enter` в списке это тот же
/// `Enter`, что и в таблице, потому что это и есть таблица.
class CombinedView extends StatefulWidget {
  const CombinedView({super.key, required this.panel, required this.settings, required this.save});

  /// Имя вида — оно же ключ настройки панели.
  static const String viewId = 'tree+';

  final Panel panel;

  /// Настройки видов: доля под деревом и всё, что нужно самим столбцам.
  final PanelsSettings Function() settings;

  /// Записать настройки: доля правится перетаскиванием.
  final VoidCallback save;

  @override
  State<CombinedView> createState() => _CombinedViewState();
}

class _CombinedViewState extends State<CombinedView> {
  /// Сколько тишины ждать, прежде чем читать каталог под курсором дерева.
  ///
  /// Стрелку держат нажатой, и читать на каждый шаг незачем: курсор идёт без
  /// задержки, придержано только чтение
  /// (`docs/spec/panel-view-combined.md`, §5).
  static const Duration _followDelay = Duration(milliseconds: 150);

  /// Меньше этого столбцу не стать: путь в дереве и так режется.
  static const double _minColumnWidth = 120;

  Application? _app;
  ViewportPosition? _side;

  /// Столбцы: дерево — первая сессия слота, список — вторая. Порядок сессий и
  /// есть порядок столбцов, а показанной бывает любая из них — та, в которой
  /// стоит курсор.
  Panel? _tree;
  Panel? _list;

  Timer? _follow;

  /// Тот же приём, что у [_follow], но в обратную сторону: дерево догоняет
  /// список следующим тактом, а не изнутри его уведомления.
  Timer? _catchUp;

  /// Заведение спутника идёт к ядру и возвращается кадром позже — второй раз
  /// просить не надо.
  bool _asking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app ??= AppScope.read(context);
    _side ??= _app?.view.positionOf(widget.panel);
    _findColumns();
  }

  @override
  void dispose() {
    _follow?.cancel();
    _catchUp?.cancel();
    _tree?.removeListener(_treeMoved);
    _list?.removeListener(_listMoved);
    super.dispose();
  }

  /// Разобрать слот на столбцы, а если сессия в нём одна — попросить вторую.
  ///
  /// Спутник встаёт **первым**: дерево всегда слева, и порядок сессий это и
  /// означает.
  void _findColumns() {
    final app = _app;
    final side = _side;
    if (app == null || side == null) {
      return;
    }

    final panels = app.panelsAt(side);
    if (panels.length < 2) {
      if (_asking) {
        return;
      }
      _asking = true;
      unawaited(
        app.openPanel(side, like: widget.panel, at: 0).then((_) {
          _asking = false;
          if (mounted) {
            setState(_findColumns);
          }
        }),
      );
      return;
    }

    final tree = panels[0];
    final list = panels[1];
    if (identical(tree, _tree) && identical(list, _list)) {
      return;
    }

    _tree?.removeListener(_treeMoved);
    _list?.removeListener(_listMoved);
    _tree = tree;
    _list = list;
    unawaited(_prepare(tree, list));
  }

  /// Приготовить столбцы: вид, ветви и курсор дерева на показанном каталоге.
  ///
  /// По порядку и до того, как встанут слушатели: смена вида пересобирает
  /// строки, и курсор после неё стоит на первой — на корне источника. Пойди
  /// связка с этого места, список уехал бы в корень диска, хотя человек ничего
  /// такого не просил.
  Future<void> _prepare(Panel tree, Panel list) async {
    // Тот же вид у обеих сессий: после перезапуска столбцы должны вернуться
    // оба.
    tree.setView(CombinedView.viewId);
    list.setView(CombinedView.viewId);
    await tree.showRows(RowsKind.branches);
    await tree.openPath(list.currentPath);
    if (!mounted || !identical(_tree, tree) || !identical(_list, list)) {
      return;
    }
    tree.addListener(_treeMoved);
    list.addListener(_listMoved);
  }

  /// Каталог, который называет курсор дерева; null — называть нечего.
  ///
  /// Настоящий путь, если он есть: ветвь находок показывает найденное, а
  /// значит — каталог, из которого оно найдено (то же правило, что у `Alt-O`).
  String? _branchUnderCursor() {
    final entry = _tree?.currentEntry;
    if (entry == null || !entry.isDirectory) {
      return null;
    }
    final at = entry.realPath.isEmpty ? entry.path : entry.realPath;
    return at.isEmpty ? null : at;
  }

  /// Курсор дерева переехал — список догоняет.
  void _treeMoved() {
    final list = _list;
    final at = _branchUnderCursor();
    if (list == null || at == null || at == list.currentPath) {
      return;
    }
    _follow?.cancel();
    _follow = Timer(_followDelay, _followCursor);
  }

  /// Показать в списке то, на чём курсор дерева стоит **сейчас**.
  ///
  /// Пересчитывается на месте, а не берётся из заявки: пока шла придержка,
  /// курсор ушёл дальше — и открывать надо то, где он оказался. Иначе список
  /// уезжает назад: раскрытие ветви двигает строки, курсор на миг оказывается
  /// на родителе, и заявка с его путём переживает возвращение курсора.
  void _followCursor() {
    final list = _list;
    final at = _branchUnderCursor();
    if (!mounted || list == null || at == null || at == list.currentPath) {
      return;
    }
    unawaited(list.openPath(at));
  }

  /// Список ушёл в другой каталог сам — по `Enter` или `Bsp`: дерево догоняет.
  void _listMoved() {
    final tree = _tree;
    final list = _list;
    if (tree == null || list == null) {
      return;
    }
    final at = list.currentPath;
    if (at.isEmpty || at == tree.currentPath || at == _branchUnderCursor()) {
      return;
    }
    // **Не из самого уведомления.** Панель рассказывает о себе, разбирая
    // событие ядра, и просьба к ядру изнутри этого разбора попадает в поток
    // событий, который в этот момент как раз и вещает: «Cannot fire new event.
    // Controller is already firing an event». Поэтому — следующим тактом.
    _catchUp?.cancel();
    _catchUp = Timer(Duration.zero, _catchUpTree);
  }

  void _catchUpTree() {
    final tree = _tree;
    final at = _list?.currentPath;
    if (!mounted || tree == null || at == null || at.isEmpty || at == _branchUnderCursor()) {
      return;
    }
    // Дерево пошло за списком — а значит, догонять его обратно не нужно:
    // заявку слежения отменяем, иначе они переставляли бы друг друга.
    _follow?.cancel();
    unawaited(tree.openPath(at));
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final list = _list;
    final settings = widget.settings();
    if (tree == null || list == null) {
      // Спутник ещё не заведён: показываем то, что есть, — саму панель.
      return FileTable(panel: widget.panel, settings: widget.settings);
    }

    return FcSplitView(
      ratio: settings.treeShare,
      minWidth: _minColumnWidth,
      onRatioChanged: (value) {
        setState(() => settings.treeShare = value.clamp(PanelsSettings.minTreeShare, PanelsSettings.maxTreeShare));
        widget.save();
      },
      onCenter: () {
        setState(() => settings.treeShare = PanelsSettings.defaultTreeShare);
        widget.save();
      },
      left: TreeView(panel: tree, settings: widget.settings, rows: RowsKind.branches),
      right: FileTable(panel: list, settings: widget.settings),
    );
  }
}
