import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'panels_settings.dart';

/// Ветвь дерева каталогов.
///
/// Значение в памяти вида, а не узел ядра: узлов по эту сторону границы не
/// бывает, а дерево спрашивает только имена (`Panel.namesIn`).
class TreeBranch {
  TreeBranch({required this.path, required this.name, required this.depth});

  /// Машинный путь: он же ключ, он же то, что откроет панель.
  final String path;

  final String name;
  final int depth;

  /// Раскрыта ли ветвь. Читается она при первом раскрытии и потом помнится.
  bool expanded = false;

  /// Идёт чтение: на медленном источнике это единственный честный ответ.
  bool loading = false;

  /// Что внутри; null — не читали ни разу.
  List<TreeBranch>? children;

  bool get read => children != null;
}

/// Деревья, которые сейчас на экране: панель → её дерево.
///
/// Команде нужно **дерево**, а не «какой сейчас вид»: раскрыть ветвь может
/// только тот, кто её показывает, а показывает её вид. Список живёт ровно
/// столько, сколько сам вид: встал — записался, ушёл — вычеркнулся.
///
/// Внутри модуля панелей и наружу не выходит: это разговор вида со своими
/// командами, и приложению он неинтересен.
abstract final class PanelTrees {
  static final Map<PanelId, TreeViewState> _live = {};

  /// Дерево этой панели; null — панель показывает что-то другое.
  static TreeViewState? of(Panel panel) => _live[panel.id];

  static void register(PanelId panel, TreeViewState tree) => _live[panel] = tree;

  /// Снимается **своим** видом: пока новый вид встаёт, старый ещё не ушёл, и
  /// вычеркнуть чужую запись значило бы оставить панель без дерева.
  static void forget(PanelId panel, TreeViewState tree) {
    if (identical(_live[panel], tree)) {
      _live.remove(panel);
    }
  }
}

/// Дерево каталогов: где панель сейчас, что рядом и что внутри.
///
/// Спецификация — `docs/spec/panel-view-tree.md`.
///
/// Вид со своей навигацией (`docs/spec/panel-views.md`, §4): показывает больше
/// одного каталога и содержимое чужих спрашивает сам. Ведёт при этом **свою**
/// панель — иначе плашка пути говорила бы про один каталог, а подсвеченная
/// ветвь про другой.
class TreeView extends StatefulWidget {
  const TreeView({super.key, required this.panel, required this.settings});

  /// Имя вида — оно же ключ настройки панели.
  static const String viewId = 'tree';

  final Panel panel;

  /// Способ узнать настройки, а не их значение: их правят в окне выбора вида.
  final PanelsSettings Function() settings;

  @override
  State<TreeView> createState() => TreeViewState();
}

class TreeViewState extends State<TreeView> {
  /// Корни дерева — верхний уровень источника.
  final List<TreeBranch> _roots = [];

  /// Плоский список видимых ветвей: по нему ходит курсор и рисуется список.
  List<TreeBranch> _visible = [];

  int _cursor = 0;

  final ScrollController _scroll = ScrollController();

  /// Путь, до которого дерево уже разворачивали: панель ходит и сама (`Bsp`,
  /// окно адреса), и дерево обязано идти за ней.
  String? _revealed;

  /// Источник, для которого построено дерево: сменился — строить заново.
  String _source = '';

  /// Показ скрытых, с которым читали: `Cmd-H` перечитывает раскрытое.
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    PanelTrees.register(widget.panel.id, this);
    unawaited(_build());
  }

  @override
  void dispose() {
    PanelTrees.forget(widget.panel.id, this);
    _scroll.dispose();
    super.dispose();
  }

  /// Ветвь под курсором; null — дерево ещё пусто.
  TreeBranch? get current => _cursor >= 0 && _cursor < _visible.length ? _visible[_cursor] : null;

  /// Собрать дерево заново: корень источника и путь до текущего каталога.
  Future<void> _build() async {
    final panel = widget.panel;
    _source = panel.source.scheme + panel.source.rootPath;
    _hidden = panel.showHidden;
    _roots
      ..clear()
      ..add(TreeBranch(path: panel.source.rootPath, name: _nameOf(panel.source.rootPath), depth: 0));
    _flatten();
    await _reveal(panel.path);
  }

  /// Раскрыть дерево до этого пути и поставить на него курсор.
  ///
  /// Спускается по одной ветви: путь ребёнка складывает источник, и повторить
  /// его сложением строк нельзя — у архива и сервера он свой.
  Future<void> _reveal(String path) async {
    _revealed = path;
    var branch = _roots.first;
    while (branch.path != path) {
      await _open(branch);
      final next = (branch.children ?? const <TreeBranch>[]).where((child) => _leadsTo(child.path, path)).firstOrNull;
      if (next == null) {
        break;
      }
      // Ветвь по дороге раскрывается: путь до текущего каталога должен быть
      // виден целиком, иначе «где я» остаётся без ответа.
      branch.expanded = true;
      branch = next;
    }
    // Текущий каталог раскрыт: дерево отвечает не только «где я», но и «что
    // внутри», а за этим не надо тянуться клавишей.
    await _open(branch);
    branch.expanded = true;
    if (!mounted) {
      return;
    }
    setState(() {
      _flatten();
      final at = _visible.indexWhere((visible) => visible.path == branch.path);
      _cursor = at < 0 ? 0 : at;
    });
    _revealCursor();
  }

  /// Ведёт ли ветвь к этому пути: сам путь или его начало.
  ///
  /// Разделитель приписывается, только если его там нет: у корня путь и так
  /// кончается на `/`, и приписанный второй не совпал бы ни с чем.
  static bool _leadsTo(String branch, String path) {
    if (path == branch) {
      return true;
    }
    final prefix = branch.endsWith('/') ? branch : '$branch/';
    return path.startsWith(prefix);
  }

  /// Прочитать ветвь, если ещё не читали.
  Future<void> _open(TreeBranch branch) async {
    if (branch.read || branch.loading) {
      return;
    }
    branch.loading = true;
    if (mounted) {
      setState(() {});
    }
    final entries = await widget.panel.namesIn(branch.path);
    branch.loading = false;
    branch.children = [
      for (final entry in entries)
        if (entry.isDirectory && !entry.isParent && (widget.panel.showHidden || !entry.name.startsWith('.')))
          TreeBranch(path: entry.path, name: entry.name, depth: branch.depth + 1),
    ];
    if (mounted) {
      setState(_flatten);
    }
  }

  /// Пересобрать список видимых ветвей.
  void _flatten() {
    final visible = <TreeBranch>[];
    void walk(List<TreeBranch> branches) {
      for (final branch in branches) {
        visible.add(branch);
        if (branch.expanded) {
          walk(branch.children ?? const []);
        }
      }
    }

    walk(_roots);
    _visible = visible;
    widget.panel.pageSize = _visible.isEmpty ? 1 : _visible.length;
  }

  /// Раскрыть ветвь под курсором; уже раскрыта — шаг внутрь.
  Future<void> expand() async {
    final branch = current;
    if (branch == null) {
      return;
    }
    if (!branch.expanded) {
      await _open(branch);
      setState(() {
        branch.expanded = true;
        _flatten();
      });
      return;
    }
    if ((branch.children ?? const []).isNotEmpty) {
      _moveTo(_cursor + 1);
    }
  }

  /// Сколько ветвей видно разом: от этого шаг страницы.
  int get visibleRows => _visible.length;

  /// Переставить курсор — стрелкой, страницей, в начало или в конец.
  void moveCursor(int to) => _moveTo(to.clamp(0, _visible.isEmpty ? 0 : _visible.length - 1));

  int get cursor => _cursor;

  /// Свернуть ветвь под курсором; уже свёрнута — шаг наружу.
  void collapse() {
    final branch = current;
    if (branch == null) {
      return;
    }
    if (branch.expanded) {
      setState(() {
        branch.expanded = false;
        _flatten();
      });
      return;
    }
    final parent = _visible.lastIndexWhere((other) => other.depth < branch.depth, _cursor);
    if (parent >= 0) {
      _moveTo(parent);
    }
  }

  /// Курсор на строку списка — и панель следом, если так настроено.
  void _moveTo(int index) {
    if (index < 0 || index >= _visible.length || index == _cursor) {
      return;
    }
    setState(() => _cursor = index);
    _revealCursor();
    if (widget.settings().treeFollowsCursor) {
      _follow(_visible[index]);
    }
  }

  /// Открыть каталог ветви в своей панели.
  void _follow(TreeBranch branch) {
    if (widget.panel.path == branch.path) {
      return;
    }
    _revealed = branch.path;
    unawaited(widget.panel.openPath(branch.path));
  }

  /// `Enter`: открыть каталог и уйти в список — дерево способ дойти, а не
  /// место, где живут.
  void submit(String backTo) {
    final branch = current;
    if (branch == null) {
      return;
    }
    _follow(branch);
    unawaited(widget.panel.setView(backTo));
  }

  void _revealCursor() {
    if (!_scroll.hasClients) {
      return;
    }
    final theme = FcTheme.of(context);
    final step = theme.metrics.rowHeight + theme.metrics.rowGap;
    final top = _cursor * step;
    final bottom = top + step;
    final offset = _scroll.offset;
    final height = _scroll.position.viewportDimension;
    final target = switch (0) {
      _ when top < offset => top,
      _ when bottom > offset + height => bottom - height,
      _ => offset,
    };
    if (target != offset) {
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  static String _nameOf(String path) {
    final at = path.lastIndexOf('/');
    return at <= 0 ? path : path.substring(at + 1);
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) {
        // Панель ушла сама — окном адреса, `Bsp`, историей: дерево идёт за ней.
        if (panel.source.scheme + panel.source.rootPath != _source || panel.showHidden != _hidden) {
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_build()));
        } else if (panel.path != _revealed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reveal(panel.path)));
        }

        // Столбцов у дерева нет: `Left` и `Right` здесь свои
        // (`docs/spec/panel-view-tree.md`, §6).
        panel.columnRows = 0;

        final app = AppScope.read(context);
        final step = theme.metrics.rowHeight + theme.metrics.rowGap;
        return ListView.builder(
          controller: _scroll,
          itemExtent: step,
          itemCount: _visible.length,
          itemBuilder: (context, index) {
            final branch = _visible[index];
            return _BranchRow(
              branch: branch,
              underCursor: index == _cursor,
              panelActive: app.view.takesKeys(panel),
              onTap: () {
                app.activate(panel);
                _moveTo(index);
              },
              onToggle: () {
                app.activate(panel);
                if (branch.expanded) {
                  setState(() {
                    branch.expanded = false;
                    _flatten();
                  });
                } else {
                  unawaited(
                    _open(branch).then((_) {
                      if (mounted) {
                        setState(() {
                          branch.expanded = true;
                          _flatten();
                        });
                      }
                    }),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

/// Одна ветвь: отступ по глубине, знак раскрытия, значок папки, имя.
class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.underCursor,
    required this.panelActive,
    required this.onTap,
    required this.onToggle,
  });

  final TreeBranch branch;
  final bool underCursor;
  final bool panelActive;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  bool get _selected => underCursor && panelActive;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final icons = theme.icons;

    final style = _selected ? theme.rowStyle.copyWith(color: colors.cursorText) : theme.rowStyle;
    final glyph = TextStyle(
      fontFamily: icons.fontFamily,
      fontSize: metrics.fontSize,
      color: _selected ? colors.iconSelected : colors.icon,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(bottom: metrics.rowGap),
        child: DecoratedBox(
          decoration: BoxDecoration(color: _selected ? colors.cursorBackground : null),
          child: Padding(
            // Слева — то же поле, что у строки списка: панели рядом, и их
            // содержимое обязано начинаться на одной вертикали.
            padding: EdgeInsets.only(left: metrics.iconLeftPadding + branch.depth * metrics.dialogGap),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: SizedBox(
                    width: metrics.fontSize,
                    child: Text(
                      branch.loading
                          ? '…'
                          : branch.expanded
                          ? String.fromCharCode(icons.caretDown.codePoint)
                          : String.fromCharCode(icons.caretRight.codePoint),
                      style: branch.loading ? style : glyph,
                    ),
                  ),
                ),
                SizedBox(width: metrics.iconGap),
                Text(String.fromCharCode(icons.folder.codePoint), style: glyph),
                SizedBox(width: metrics.iconGap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: metrics.panelRightPadding),
                    child: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
