import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'file_table_header.dart';
import 'file_type_icon.dart';
import 'panel_drag.dart';
import 'panels_settings.dart';

/// Ветвь дерева каталогов.
///
/// Значение в памяти вида, а не узел ядра: узлов по эту сторону границы не
/// бывает, а дерево спрашивает только имена (`Panel.namesIn`).
class TreeBranch {
  TreeBranch({required this.path, required this.entry, required this.depth, this.parent});

  /// Машинный путь: он же ключ, он же то, чем ветвь находят.
  final String path;

  /// Ветвь, в которой эта лежит; null — корень источника.
  ///
  /// Ею и отвечает дерево на вопрос «в каком каталоге курсор»: каталог панели
  /// идёт за курсором, а складывать путь из строки нельзя — у архива и сервера
  /// он свой (`docs/spec/panel-view-tree.md`, §3).
  final TreeBranch? parent;

  /// Сам объект — значением: по нему рисуются значок и имя, теми же правилами,
  /// что в списке файлов.
  final FileEntry entry;

  final int depth;

  String get name => entry.name;

  /// Раскрывать можно только каталог: у файла внутри ничего нет.
  bool get isDirectory => entry.isDirectory;

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

  /// Настройки видов: показывать ли размер. Способом узнать, а не значением —
  /// флажок правят в окне выбора вида, и следующий же кадр обязан его учесть.
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

  /// Каталог, за которым панель идёт **по нашей просьбе**; null — дошла.
  ///
  /// Пока она идёт, она говорит про **прежний** каталог: на медленном
  /// источнике — несколько кадров, на сервере — заметно дольше.
  /// Разворачиваться на это нельзя. Дерево уводило курсор назад, к тому месту,
  /// откуда его только что подвинули, — и следующий `Space` снимал пометку,
  /// которую сам же и поставил. Отсюда и мерцание: разворот, шаг курсора,
  /// новая просьба — и всё сначала (`docs/spec/panel-view-tree.md`, §3).
  String? _following;

  /// Источник, для которого построено дерево: сменился — строить заново.
  String _source = '';

  /// Показ скрытых, с которым читали: `Cmd-H` перечитывает раскрытое.
  bool _hidden = false;

  /// Окно, в пределах которого два щелчка по одной ветви считаются двойным.
  static const Duration _doubleTapWindow = Duration(milliseconds: 400);

  int _lastTapIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// Ветвь, в которую бросили: её раскрывают сразу, а перечитывают, когда
  /// работа кончится (`docs/spec/drag-and-drop.md`, §4).
  String? _dropped;

  /// Работа после броска и правда началась: без этого первая же кончившаяся
  /// чужая работа перечитала бы ветвь впустую.
  bool _sawWork = false;

  Operations? _operations;

  @override
  void initState() {
    super.initState();
    PanelTrees.register(widget.panel.id, this);
    unawaited(_build());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Работы слушаются ради брошенного: каталог раскрыт сразу, а появившееся в
    // нём видно только после перечитывания.
    final operations = AppScope.read(context).operations;
    if (identical(operations, _operations)) {
      return;
    }
    _operations?.removeListener(_onOperations);
    _operations = operations..addListener(_onOperations);
  }

  @override
  void dispose() {
    PanelTrees.forget(widget.panel.id, this);
    _operations?.removeListener(_onOperations);
    _scroll.dispose();
    super.dispose();
  }

  /// Работа кончилась — перечитать ветвь, в которую бросили.
  ///
  /// Дерево показывает много каталогов разом, и перечитывание панелей до него
  /// не доходит: панель стоит там, где курсор, а бросали куда указали.
  void _onOperations() {
    if (_dropped == null) {
      return;
    }
    if (_operations?.all.isNotEmpty ?? false) {
      _sawWork = true;
      return;
    }
    if (!_sawWork) {
      return;
    }
    final path = _dropped;
    _dropped = null;
    _sawWork = false;
    unawaited(refresh(path!));
  }

  /// Перечитать ветвь по пути и оставить её раскрытой.
  ///
  /// Прочитанное дерево помнит (`docs/spec/panel-view-tree.md`, §5), а после
  /// работы память врёт: в каталоге появилось или исчезло.
  Future<void> refresh(String path) async {
    final branch = _branchAt(path);
    if (branch == null) {
      return;
    }
    branch.children = null;
    await _open(branch);
    if (!mounted) {
      return;
    }
    setState(() {
      branch.expanded = true;
      _flatten();
    });
  }

  /// Вопрос уже задан: второго, пока не ответили, не будет.
  bool _asking = false;

  /// О чём спрашивали в прошлый раз.
  String _askedFor = '';

  /// Спросить размеры показанных ветвей — один раз на смену показанного.
  ///
  /// Дальше числа приходят сами: панель везёт их событиями по путям, и дерево
  /// берёт их оттуда же, откуда таблица (`docs/spec/panel-view-tree.md`, §5).
  /// Вопрос нужен ровно затем, чтобы только что раскрытая ветвь узнала о том,
  /// что посчитали до неё.
  void _askShownSizes() {
    final paths = [for (final branch in _visible) branch.path];
    final asked = paths.join('\n');
    if (_asking || asked == _askedFor) {
      return;
    }
    _asking = true;
    _askedFor = asked;
    unawaited(
      widget.panel.sizesOf(paths).then((sizes) {
        _asking = false;
        if (mounted && sizes.isNotEmpty) {
          setState(() {});
        }
      }),
    );
  }

  /// Ветвь по пути — среди прочитанных; null — такой не показано.
  TreeBranch? _branchAt(String path) {
    TreeBranch? found;
    void walk(List<TreeBranch> branches) {
      for (final branch in branches) {
        if (branch.path == path) {
          found = branch;
          return;
        }
        walk(branch.children ?? const []);
      }
    }

    walk(_roots);
    return found;
  }

  /// Ветвь под курсором; null — дерево ещё пусто.
  TreeBranch? get current => _cursor >= 0 && _cursor < _visible.length ? _visible[_cursor] : null;

  /// Собрать дерево заново: корень источника и путь до текущего каталога.
  Future<void> _build() async {
    final panel = widget.panel;
    _following = null;
    _source = panel.source.scheme + panel.source.rootPath;
    _hidden = panel.showHidden;
    _roots
      ..clear()
      ..add(
        TreeBranch(
          path: panel.source.rootPath,
          entry: FileEntry(
            // Корень источника подписан корнем — `/`. Имя из пути тут не
            // добыть: у местной ФС это и правда `/`, а у сервера путь к корню
            // выглядит адресом (`sftp:koldoon@shark/`), и последнее его звено
            // либо пусто, либо вовсе не имя. Корень же у всех источников
            // называется одинаково.
            name: '/',
            kind: EntryKind.directory,
            path: panel.source.rootPath,
          ),
          depth: 0,
        ),
      );
    _flatten();
    // До объекта под курсором панели, а не только до её каталога: вид со своей
    // навигацией обязан встать там же, где стоял курсор
    // (`docs/spec/panel-views.md`, §5), — и тогда каталог панели уже тот,
    // который под курсором дерева, и идти никуда не надо.
    await _reveal(panel.path, name: panel.currentEntry?.name);
  }

  /// Раскрыть дерево до этого пути и поставить на него курсор.
  ///
  /// Спускается по одной ветви: путь ребёнка складывает источник, и повторить
  /// его сложением строк нельзя — у архива и сервера он свой.
  Future<void> _reveal(String path, {String? name}) async {
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
      // Курсор на объект, если он назван и виден: иначе — на сам каталог. «..»
      // в дереве нет, и по имени он не находится, что и требуется.
      final wanted =
          name == null ? -1 : _visible.indexWhere((visible) => visible.parent == branch && visible.name == name);
      final at = wanted >= 0 ? wanted : _visible.indexWhere((visible) => visible.path == branch.path);
      _cursor = at < 0 ? 0 : at;
    });
    _revealCursor();
  }

  /// Каталог панели — тот, в котором лежит ветвь под курсором.
  ///
  /// Не открытие: панель не занята, пометка остаётся, а тот же каталог не
  /// перечитывается (`docs/spec/panel-view-tree.md`, §3). Корень источника ни в
  /// чём не лежит — на нём панель остаётся там, где стояла.
  void _followCursor() {
    final branch = current;
    final parent = branch?.parent;
    if (branch == null || parent == null) {
      return;
    }
    // Панель уходит туда сама, и обратной волной дерево разворачивать незачем:
    // оно уже там, где надо.
    _revealed = parent.path;
    _following = parent.path;
    widget.panel.follow(parent.path, name: branch.name);
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
    // Каталоги вперёд файлов, и то и другое по имени: тот же порядок, каким
    // список показывает каталог.
    final kept = [
      for (final entry in entries)
        if (!entry.isParent && (widget.panel.showHidden || !entry.name.startsWith('.'))) entry,
    ]..sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    branch.children = [
      for (final entry in kept) TreeBranch(path: entry.path, entry: entry, depth: branch.depth + 1, parent: branch),
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

  /// Раскрыть ветвь под курсором.
  Future<void> expand() async {
    final branch = current;
    if (branch == null || !branch.isDirectory || branch.expanded) {
      return;
    }
    await toggle();
  }

  /// Сколько ветвей видно разом: от этого шаг страницы.
  int get visibleRows => _visible.length;

  /// Переставить курсор — стрелкой, страницей, в начало или в конец.
  void moveCursor(int to) => _moveTo(to.clamp(0, _visible.isEmpty ? 0 : _visible.length - 1));

  int get cursor => _cursor;

  /// Пометить ветвь под курсором и шагнуть вниз — та же клавиша и та же
  /// привычка, что в списке (`docs/spec/panel-view-tree.md`, §7).
  ///
  /// Помечается **объект**, а не строка: пометка едет путём, и панель к этому
  /// времени уже стоит в каталоге ветви (§3). Корень источника не помечается —
  /// он ни в каком каталоге не лежит.
  void toggleMark() {
    final branch = current;
    if (branch == null || branch.parent == null) {
      return;
    }
    final panel = widget.panel;
    if (panel.isMarked(branch.entry)) {
      panel.unmark(branch.entry);
    } else {
      panel.mark(branch.entry);
    }
    moveCursor(_cursor + 1);
  }

  /// Свернуть ветвь под курсором, а сворачивать нечего — уйти к родителю.
  ///
  /// Два шага одной клавишей, и порядок у них привычный по редакторам кода:
  /// `Left` на файле или сложенной ветви поднимает курсор в каталог, где она
  /// лежит, а следующий `Left` — уже на раскрытом каталоге — сворачивает его
  /// (`docs/spec/panel-view-tree.md`, §6). Так из глубины выходят той же
  /// клавишей, которой закрывают, и думать, какая из двух нужна сейчас, не
  /// приходится.
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
    // Родитель на виду всегда: раз ветвь видна, то видна и та, из которой её
    // раскрыли. У корня родителя нет — там `Left` не делает ничего.
    final at = branch.parent == null ? -1 : _visible.indexOf(branch.parent!);
    if (at >= 0) {
      _moveTo(at);
    }
  }

  /// Курсор на строку — и **только**: панель за ним не идёт.
  ///
  /// Дерево здесь показывает, а работает с найденным следующий вид — дерево с
  /// содержимым рядом (`docs/spec/panel-view-tree.md`, §3).
  void _moveTo(int index) {
    if (index < 0 || index >= _visible.length || index == _cursor) {
      return;
    }
    setState(() => _cursor = index);
    _followCursor();
    _revealCursor();
  }

  /// Раскрыть ветвь под курсором; раскрытую — свернуть.
  Future<void> toggle() async {
    final branch = current;
    if (branch == null || !branch.isDirectory) {
      return;
    }
    if (branch.expanded) {
      collapse();
      return;
    }
    await _open(branch);
    if (!mounted) {
      return;
    }
    setState(() {
      branch.expanded = true;
      _flatten();
    });
  }

  void _revealCursor() {
    if (!_scroll.hasClients) {
      return;
    }
    // Тот же шаг, каким нарисованы строки: считать его вторым способом значит
    // однажды разъехаться с самим собой.
    final step = _step > 0 ? _step : FcTheme.of(context).metrics.rowHeight;
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

  /// Высота строки дерева вместе с просветом; 0 — разметки ещё не было.
  double _step = 0;

  /// Высота шапки: она входит в область, но не в список, и попадание броском
  /// считается от первой строки, а не от верха области.
  double _headerHeight = 0;

  /// Ветвь под точкой — в местных координатах области.
  TreeBranch? _branchUnder(Offset local) {
    if (_step <= 0 || local.dy < _headerHeight) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = ((local.dy - _headerHeight + offset) / _step).floor();
    return index >= 0 && index < _visible.length ? _visible[index] : null;
  }

  /// Куда попадёт брошенное: в каталог под указателем, а указали на файл — в
  /// тот, где он лежит.
  ///
  /// В дереве каталогов видно много разом, и «каталог панели» тут — случайное
  /// место, где стоит курсор. Поэтому мимо ветвей бросать некуда: подсветки
  /// нет, отпускание ничего не делает (`docs/spec/drag-and-drop.md`, §4).
  DropSpot? _spotAt(Offset local) {
    final panel = widget.panel;
    if (!panel.source.canWrite) {
      return null;
    }
    final under = _branchUnder(local);
    final directory =
        under == null
            ? null
            : under.isDirectory
            ? under
            : under.parent;
    if (directory == null) {
      return null;
    }
    return DropSpot(destination: directory.path, entry: directory.entry);
  }

  /// Обводится **та ветвь, в которую ляжет**: указали на файл — горит его
  /// каталог, и видно, куда именно попадёт брошенное.
  Rect? _highlightOf(DropSpot spot) {
    final at = _visible.indexWhere((branch) => branch.path == spot.destination);
    if (at < 0 || _step <= 0) {
      return null;
    }
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return Rect.fromLTWH(0, _headerHeight + at * _step - offset, double.infinity, _step);
  }

  /// Бросили — раскрываем: в закрытую ветвь файл уедет молча, и человек не
  /// увидит, что он там появился. Перечитается она, когда работа кончится.
  void _onDropped(DropSpot spot) {
    _dropped = spot.destination;
    _sawWork = false;
    final branch = _branchAt(spot.destination);
    if (branch == null || branch.expanded) {
      return;
    }
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

  /// Щелчок ставит курсор, двойной — раскрывает ветвь или сворачивает её.
  ///
  /// То же, что делает `Enter`: вид со своей навигацией обязан отвечать и на
  /// двойной щелчок (`docs/spec/panel-views.md`, §9). Распознаётся вручную —
  /// как в таблице: штатный `onDoubleTap` заставляет ждать окно двойного
  /// щелчка перед **первым**, и курсор начинает опаздывать.
  void _onTap(int index) {
    final now = DateTime.now();
    final again = index == _lastTapIndex && now.difference(_lastTapTime) < _doubleTapWindow;
    _lastTapIndex = index;
    _lastTapTime = now;

    AppScope.read(context).activate(widget.panel);
    _moveTo(index);
    if (again) {
      unawaited(toggle());
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) {
        // Панель ушла сама — окном адреса, `Bsp`, историей: дерево идёт за ней.
        // Но сперва надо отличить «ушла сама» от «ещё не дошла туда, куда мы
        // её послали»: пока она догоняет курсор, она говорит про прежний
        // каталог, и разворот на него увёл бы курсор назад.
        if (panel.source.scheme + panel.source.rootPath != _source || panel.showHidden != _hidden) {
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_build()));
        } else if (panel.path == _following) {
          _following = null;
        } else if (_following == null && panel.path != _revealed) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(_reveal(panel.path, name: panel.currentEntry?.name)),
          );
        }

        // Столбцов у дерева нет: `Left` и `Right` здесь свои
        // (`docs/spec/panel-view-tree.md`, §6).
        panel.columnRows = 0;

        final app = AppScope.read(context);
        // Шаг строки — тот же, что в списке: панели стоят рядом, и строки
        // обязаны сходиться. Считается он одним местом на оба вида
        // (`FileIconSize.listRow`), иначе значок настроят покрупнее — и
        // разъедутся (`docs/spec/panel-view-tree.md`, §4).
        final step = FileIconSize.listRow(theme.metrics, app.fileIcons);
        _step = step;
        _headerHeight = theme.metrics.headerRowHeight;

        // Колонки те же, что у таблицы, и ширина у размера та же: дерево
        // показывает то же самое, и мерить это другой меркой незачем
        // (`docs/spec/panel-view-tree.md`, §4).
        final showSize = widget.settings().treeSize;
        final sizeWidth = _sizeColumn.width;
        // Поле справа принадлежит содержимому, а не подсветке строки, — как и
        // в таблице.
        final inset = theme.metrics.panelRightPadding;

        // Размер у ветви один и берётся из одного места — из того же, откуда
        // его берёт таблица. Двух источников тут уже было достаточно, чтобы
        // число прыгало между свежим и вчерашним
        // (`docs/spec/panel-view-tree.md`, §5).
        if (showSize) {
          _askShownSizes();
        }
        int sizeOf(TreeBranch branch) => panel.sizeOf(branch.path) ?? branch.entry.size;

        final list = ListView.builder(
          controller: _scroll,
          itemExtent: step,
          itemCount: _visible.length,
          itemBuilder: (context, index) {
            final branch = _visible[index];
            final row = _BranchRow(
              branch: branch,
              underCursor: index == _cursor,
              marked: panel.isMarked(branch.entry),
              size: showSize ? sizeOf(branch) : FileEntry.unknownSize,
              sizeWidth: showSize ? sizeWidth : 0,
              inset: inset,
              panelActive: app.view.takesKeys(panel),
              onTap: () => _onTap(index),
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
            // Тянут за ветвь то же, что тянут за строку списка: объект, а не
            // картинку (`panel_drag.dart`).
            return panelDragSource(context: context, panel: panel, entry: branch.entry, child: row);
          },
        );

        final content = Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_TreeHeader(showSize: showSize, sizeWidth: sizeWidth, inset: inset), Expanded(child: list)],
            ),
            // Линейка идёт от шапки и поверх строк — как в таблице, где она
            // объявлена после списка, чтобы подсветка курсора её не закрывала.
            if (showSize)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SizeDividerPainter(
                      right: sizeWidth + inset,
                      color: theme.colors.columnDivider,
                      inset: theme.metrics.strokeWidth,
                    ),
                  ),
                ),
              ),
          ],
        );

        // Бросают в каталог под указателем, а не в каталог панели: дерево
        // показывает много каталогов разом.
        return PanelDropArea(
          panel: panel,
          spotAt: _spotAt,
          highlightOf: _highlightOf,
          onDropped: _onDropped,
          child: content,
        );
      },
    );
  }
}

/// Колонки дерева: сама ветвь и размер.
///
/// Те же `ColumnSpec`, что у таблицы, и та же ширина у размера: дерево
/// показывает то же самое, и мерить это другой меркой незачем. Здесь их две; с
/// датой станет три (`docs/spec/panel-view-tree.md`, §4).
const ColumnSpec _treeColumn = ColumnSpec(id: FsColumn.tree, width: 0, pinned: true);
const ColumnSpec _sizeColumn = ColumnSpec(id: FsColumn.size, width: 64, align: ColumnAlign.end);

/// Шапка дерева: те же заголовки, что у таблицы.
///
/// Своя, а не `FileTableHeader`: у того три жеста — сортировка, перестановка
/// колонок и тяга ширины, — и все три дереву обещать нечем. Ячейка при этом та
/// же самая, чтобы набор и середина совпадали до точки.
class _TreeHeader extends StatelessWidget {
  const _TreeHeader({required this.showSize, required this.sizeWidth, required this.inset});

  final bool showSize;
  final double sizeWidth;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    return SizedBox(
      height: theme.metrics.headerRowHeight,
      child: Row(
        children: [
          const Expanded(
            child: FileTableHeaderCell(column: _treeColumn, sorted: false, direction: SortDirection.ascending),
          ),
          if (showSize)
            SizedBox(
              width: sizeWidth,
              child: const FileTableHeaderCell(column: _sizeColumn, sorted: false, direction: SortDirection.ascending),
            ),
          SizedBox(width: inset),
        ],
      ),
    );
  }
}

/// Линейка слева от колонки размера.
///
/// Одна на всё дерево: колонок здесь две, и разделять больше нечего. Не доходит
/// до низа на толщину линии — по той же причине, что в таблице: сойдись она с
/// линейкой над строкой состояния, получился бы перекрёсток, и глаз читал бы
/// его как рамку, которой нет.
class _SizeDividerPainter extends CustomPainter {
  const _SizeDividerPainter({required this.right, required this.color, required this.inset});

  /// На сколько линейка отстоит от правого края области.
  final double right;
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = (size.width - right).roundToDouble() + 0.5;
    canvas.drawLine(
      Offset(dx, 0),
      Offset(dx, size.height - inset),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SizeDividerPainter old) => old.right != right || old.color != color || old.inset != inset;
}

/// Одна ветвь: отступ по глубине, знак раскрытия, значок папки, имя.
class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.underCursor,
    required this.marked,
    required this.size,
    required this.sizeWidth,
    required this.inset,
    required this.panelActive,
    required this.onTap,
    required this.onToggle,
  });

  final TreeBranch branch;
  final bool underCursor;

  /// Помечена ли ветвь. Показывается теми же цветами, что в списке: пометка в
  /// панели одна, и выглядеть она обязана одинаково
  /// (`docs/spec/panel-view-tree.md`, §7).
  final bool marked;

  /// Размер объекта; [FileEntry.unknownSize] — показывать нечего: у каталога
  /// его ещё не считали, а колонку могли и выключить.
  final int size;

  /// Ширина колонки размера и поле справа — те же, что у шапки: колонка на то и
  /// колонка, чтобы числа стояли под своим заголовком.
  final double sizeWidth;
  final double inset;

  final bool panelActive;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  bool get _selected => underCursor && panelActive;

  /// Знак раскрытия: у каталога — шеврон, у файла ничего.
  ///
  /// Пусто, а не пропущенный квадрат: имена ветвей одного уровня начинаются с
  /// одной вертикали независимо от того, есть внутри что-нибудь или нет
  /// (`docs/spec/panel-view-tree.md`, §4).
  String _mark(FcIcons icons) {
    if (!branch.isDirectory) {
      return '';
    }
    if (branch.loading) {
      return '…';
    }
    return String.fromCharCode(branch.expanded ? icons.branchOpen.codePoint : icons.branchClosed.codePoint);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final colors = theme.colors;
    final metrics = theme.metrics;
    final icons = theme.icons;

    // Знак раскрытия занимает **тот же квадрат**, что значок объекта, и отбит
    // от него на `treeMarkGap`. Отсюда и шаг вглубь — квадрат вместе с этим
    // просветом: знак дочерней ветви приходится серединой на середину значка
    // родительской (`docs/spec/panel-view-tree.md`, §4).
    final square = FileIconSize.of(metrics, AppScope.read(context).fileIcons);
    final indent = square + metrics.treeMarkGap;

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
          // Слоями снизу вверх, как в списке: обычная → помеченная → под
          // курсором (`FileTableRow`).
          decoration: BoxDecoration(
            color:
                _selected
                    ? colors.cursorBackground
                    : marked
                    ? colors.markedBackground
                    : null,
          ),
          child: Stack(
            children: [
              Padding(
                // Слева — то же поле, что у строки списка: панели рядом, и их
                // содержимое обязано начинаться на одной вертикали.
                padding: EdgeInsets.only(left: metrics.iconLeftPadding + branch.depth * indent),
                // Те же две поправки, что у строки списка: содержимое опущено
                // относительно подсветки, а имя — относительно значка. Панели
                // стоят рядом, и строка дерева обязана совпадать со строкой списка
                // до точки (`FcMetrics.rowContentVerticalNudge`,
                // `rowTextVerticalNudge`).
                child: Transform.translate(
                  offset: Offset(0, metrics.rowContentVerticalNudge),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggle,
                        child: SizedBox(
                          width: square,
                          // По середине квадрата, а не по левому его краю: глиф
                          // угла узкий, и прижатый влево он отходил бы от значка
                          // на полквадрата.
                          child: Center(child: Text(_mark(icons), style: branch.loading ? style : glyph)),
                        ),
                      ),
                      SizedBox(width: metrics.treeMarkGap),
                      // Значок тот же, что в списке: у каталога папка, у файла его
                      // собственный — правило одно на приложение
                      // (`docs/spec/file-icons.md`).
                      FileTypeIcon(entry: branch.entry, selected: _selected),
                      SizedBox(width: metrics.iconGap),
                      Expanded(
                        child: Transform.translate(
                          offset: Offset(0, metrics.rowTextVerticalNudge),
                          child: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                        ),
                      ),
                      // Колонка размера — своей ширины и под своим заголовком:
                      // число прижато к правому её краю, как в таблице
                      // (`docs/spec/panel-view-tree.md`, §4).
                      if (sizeWidth > 0)
                        SizedBox(
                          width: sizeWidth,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: metrics.cellPadding),
                            child: Transform.translate(
                              offset: Offset(0, metrics.rowTextVerticalNudge),
                              child: Text(formatSize(size), maxLines: 1, textAlign: TextAlign.right, style: style),
                            ),
                          ),
                        ),
                      SizedBox(width: inset),
                    ],
                  ),
                ),
              ),
              // Полоса пометки поверх фона: она должна читаться и тогда, когда
              // ветвь вдобавок под курсором.
              if (marked)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: metrics.markedBarWidth,
                  child: ColoredBox(color: colors.markedBar),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
