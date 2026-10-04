import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'listing_cache.dart';
import 'node_list.dart';

/// Строки дерева: набор корней, развёрнутый построчно.
///
/// Второй набор строк после каталога (`docs/spec/panel-node-list.md`, §3) и
/// первый **маппер**: он не читает содержимое сам, а разворачивает раскрытые
/// ветви в плоский список и проставляет строкам глубину и раскрытость.
///
/// Состояние раскрытого живёт **здесь**, а не на экране: от этого зависит и то,
/// что раскрытое переживает перезапуск, и то, что курсор по дереву больше не
/// водит панель за собой.
///
/// **Содержимое ветви читает провайдер самого узла**, а не корня: найденный
/// каталог раскрывается настоящим источником, каким бы ни был набор.
/// Чем кончилось раскрытие: сколько ветвей открыто и упёрлось ли в предел.
class TreeExpansion {
  const TreeExpansion({required this.opened, required this.stopped});

  final int opened;

  /// Предел достигнут: дальше человек раскрывает сам.
  final bool stopped;
}

/// Кто раскрывает ветвь, которая каталогом не является: архив.
///
/// Набор строк не знает ни реестра источников, ни аренды — и не должен: его
/// дело развернуть ветви в строки. Монтирует и держит аренду сессия
/// (`docs/spec/panel-view-tree.md`, §4б).
abstract interface class BranchMounter {
  /// Можно ли раскрыть этот узел. Спрашивается на каждой строке — поэтому
  /// синхронно и дёшево, по расширению, как решает и `Enter` в списке.
  bool mountable(FsNode node);

  /// Смонтировать и отдать корень источника; null — не вышло.
  Future<DirectoryNode?> mount(FsNode node);
}

class TreeNodeList implements NodeList {
  TreeNodeList({
    required List<DirectoryNode> roots,
    Iterable<String> expanded = const [],
    this.directoriesOnly = false,
    this.compact = false,
    this.mounter,
  }) : _rootDirectories = List.unmodifiable(roots),
       _roots = [for (final root in roots) _Branch(root)],
       _expanded = {...expanded} {
    assert(roots.isNotEmpty, 'дерево без корней показывать нечем');
  }

  /// Кто откроет архив под курсором; null — некому, и архив остаётся файлом.
  final BranchMounter? mounter;

  /// Раскрываемо ли: каталог — всегда, архив — если есть кому его открыть.
  bool _isBranch(FsNode node) => node is DirectoryNode || (mounter?.mountable(node) ?? false);

  /// Каталог ветви: сам узел или корень смонтированного источника.
  ///
  /// [mount] — можно ли ради этого монтировать. Ложь у тех, кто ходит по
  /// дереву сам: «раскрыть всё» архивы не открывает (§4б).
  Future<DirectoryNode?> _directoryOf(_Branch branch, {bool mount = true}) async {
    final node = branch.node;
    if (node is DirectoryNode) {
      return node;
    }
    if (branch.mounted != null || !mount) {
      return branch.mounted;
    }
    final mounter = this.mounter;
    if (mounter == null || !mounter.mountable(node)) {
      return null;
    }
    return branch.mounted = await mounter.mount(node);
  }

  /// Показывать только каталоги: файлы в такие строки не попадают вовсе.
  ///
  /// Просьба вида, а не свойство дерева: у комбинированного вида файлы живут в
  /// соседнем столбце, и вторым списком они не нужны
  /// (`docs/spec/panel-view-combined.md`, §4). Отбор стоит здесь, а не в виде:
  /// вид не отбирает строки, он их рисует.
  final bool directoriesOnly;

  /// Склеивать цепочки: каталог, в котором ровно один показанный подкаталог,
  /// стоит одной строкой с ним (`docs/spec/panel-view-compact-tree.md`, §2).
  ///
  /// Просьба вида, как и [directoriesOnly]. Выключен — строки выходят ровно те
  /// же, что у обычного дерева: склеивающий цикл не делает ни шага.
  final bool compact;

  /// Подписи строк-цепочек: строка → имена поглощённых каталогов через `/`.
  ///
  /// Здесь, а не на узле: узлы общие у нескольких наборов (находки показаны и
  /// деревом, и списком), и подпись на узле утекала бы в чужой список.
  /// Пересобирается на каждой раскладке.
  final Map<FsNode, String> _heads = Map.identity();

  /// Поглощённый путь → строка, которой он показан.
  final Map<String, FsNode> _absorbed = {};

  /// Голова цепочки у строки; пусто — строка стоит сама по себе.
  String chainHeadOf(FsNode row) => _heads[row] ?? '';

  /// Строка, которой показан поглощённый цепочкой путь; null — путь не
  /// поглощён (или его в строках нет вовсе).
  ///
  /// Курсору: раскрыли `a`, а внутри один `b` — строки `a` больше нет, она
  /// стала строкой `a/b`, и курсор обязан встать на неё, а не уйти к предку
  /// (§5).
  FsNode? shownAs(String path) => _absorbed[path];

  final List<DirectoryNode> _rootDirectories;

  final List<_Branch> _roots;

  /// Пути раскрытых ветвей. Путями, а не узлами: узлы переживают чтение не
  /// всегда, а путь — всегда.
  final Set<String> _expanded;

  @override
  List<FsNode> get roots => _rootDirectories;

  /// Каталог набора — первый корень: к нему привязаны аренда и оболочка, пока
  /// курсор не сказал иного ([currentPathFor]).
  @override
  DirectoryNode get directory => _rootDirectories.first;

  /// Раскрытое — то, что стоит сохранить и восстановить при следующем запуске.
  Set<String> get expandedPaths => {..._expanded};

  /// Кэш листингов дереву не помощник: он помнит каталог целиком, а здесь
  /// каждая ветвь читается своим `listChildren` и живёт до сворачивания.
  @override
  List<FsNode>? shown(ListingCache? cache, {required bool includeHidden}) => null;

  @override
  void remember(ListingCache? cache, List<FsNode> rows, {required bool includeHidden}) {}

  /// Куда пойдёт операция: каталог строки под курсором.
  ///
  /// Не корень и не «показанный каталог»: в дереве видно много каталогов
  /// сразу, и единственный осмысленный ответ — тот, где стоит курсор.
  ///
  /// null — курсор на корне: он ни в чём не лежит, и панель остаётся там, где
  /// стояла (`docs/spec/panel-view-tree.md`, §3).
  @override
  String? currentPathFor(FsNode? cursor) {
    if (cursor == null) {
      return null;
    }
    // Корень набора — тот, что человек выбрал, а не тот, у кого нет родителя:
    // ветвь `/home` в файловой системе лежит в `/`, но если дерево начинается
    // с неё, выше подниматься некуда.
    final at = cursor.pathString;
    if (_rootDirectories.any((root) => root.pathString == at)) {
      return null;
    }
    return cursor.parentDirectory?.displayPath;
  }

  @override
  Operation<void, List<FsNode>> read({required NodeListOrder order}) {
    return TaskOperation<void, List<FsNode>>((op, _) async {
      for (final branch in _roots) {
        await _fill(branch, op, includeHidden: order.includeHidden);
      }
      return _flatten(order);
    });
  }

  /// Строки складываются заново без чтения: ветви уже прочитаны, и смена
  /// правила — это только новый порядок.
  @override
  List<FsNode> reorder(List<FsNode> rows, NodeListOrder order) => _flatten(order);

  /// Ветвь, в которой стоит строка; null — строка сама корень.
  @override
  DirectoryNode? branchOf(FsNode row) {
    DirectoryNode? found;

    bool walk(List<_Branch> branches, DirectoryNode? parent) {
      for (final branch in branches) {
        if (identical(branch.node, row)) {
          found = parent;
          return true;
        }
        final node = branch.node;
        final dir = node is DirectoryNode ? node : branch.mounted;
        if (walk(branch.children ?? const [], dir ?? parent)) {
          return true;
        }
      }
      return false;
    }

    walk(_roots, null);
    return found;
  }

  /// Раскрыть ветвь и всё, что под ней; пустой путь — всё дерево.
  ///
  /// Читает по дороге: узнать, что там внутри, иначе нечем. Предел не
  /// перестраховка, а необходимость — «раскрыть всё» над корнем диска значит
  /// прочитать диск целиком; упёрлись в него — так и говорим
  /// (`docs/spec/panel-view-tree.md`, §6а).
  ///
  /// Дышит по времени: местный провайдер читает каталог **синхронно**, и без
  /// вдоха обход занял бы поток целиком — как это было у поиска
  /// (`SearchRun.breath`).
  Future<TreeExpansion> expandDeep(
    String path, {
    required int limit,
    required bool includeHidden,
    required OperationContext op,
  }) async {
    final start = path.isEmpty ? _roots : [_branchAt(path)];
    var opened = 0;
    var stopped = false;
    final sinceBreath = Stopwatch()..start();

    Future<void> walk(_Branch? branch) async {
      if (branch == null || stopped) {
        return;
      }
      final node = branch.node;
      if (node is! DirectoryNode) {
        return;
      }
      if (opened >= limit) {
        stopped = true;
        return;
      }
      op.checkCanceled();
      if (sinceBreath.elapsed >= _breath) {
        sinceBreath
          ..reset()
          ..start();
        await Future<void>.delayed(Duration.zero);
        op.checkCanceled();
      }

      if (_expanded.add(node.pathString)) {
        opened++;
      }
      await _fillOne(branch);
      for (final child in branch.children ?? const <_Branch>[]) {
        // Скрытое не раскрываем, пока его не показывают: читать то, чего не
        // видно, незачем.
        if (!includeHidden && child.node.name.startsWith('.')) {
          continue;
        }
        await walk(child);
      }
    }

    for (final branch in start) {
      await walk(branch);
    }
    return TreeExpansion(opened: opened, stopped: stopped);
  }

  /// Свернуть ветвь и всё, что под ней; пустой путь — всё дерево.
  ///
  /// Прочитанное не выбрасывается: свернули и развернули обратно — читать
  /// заново незачем.
  int collapseDeep(String path) {
    if (path.isEmpty) {
      final was = _expanded.length;
      _expanded.clear();
      for (final branch in _roots) {
        _forgetMountedIn(branch);
      }
      return was;
    }
    final under = _expanded.where((at) => at == path || at.startsWith('$path/')).toList();
    _expanded.removeAll(under);
    _forgetMounted(path);
    return under.length;
  }

  /// Забыть смонтированное под этим путём: сессия отпустила аренду, и
  /// прочитанное из закрытого источника — уже не ответ.
  void _forgetMounted(String path) {
    final branch = _branchAt(path);
    if (branch != null) {
      _forgetMountedIn(branch);
    }
  }

  void _forgetMountedIn(_Branch branch) {
    if (branch.mounted != null) {
      branch.mounted = null;
      branch.children = null;
      branch.hasBranches = null;
      return;
    }
    for (final child in branch.children ?? const <_Branch>[]) {
      _forgetMountedIn(child);
    }
  }

  /// Ветвь по пути; null — такой в дереве нет.
  _Branch? _branchAt(String path) {
    _Branch? found;
    bool walk(List<_Branch> branches) {
      for (final branch in branches) {
        if (branch.node.pathString == path) {
          found = branch;
          return true;
        }
        if (walk(branch.children ?? const [])) {
          return true;
        }
      }
      return false;
    }

    walk(_roots);
    return found;
  }

  /// Прочитать содержимое одной ветви, если его ещё нет.
  Future<void> _fillOne(_Branch branch, {bool mount = false}) async {
    if (branch.children != null) {
      return;
    }
    final node = await _directoryOf(branch, mount: mount);
    if (node == null) {
      return;
    }
    try {
      final children = await node.provider.listChildren(node);
      branch.children = [for (final child in children) _Branch(child)];
    } on Object {
      // В ветвь не пустили — она просто останется пустой, как и в списке.
      branch.children = const [];
    }
  }

  /// Есть ли в прочитанной ветви свои ветви; null — не читали, и врать нечем.
  bool? _branchesIn(_Branch branch, bool includeHidden) {
    final children = branch.children;
    if (children == null) {
      return null;
    }
    return children.any((child) => _isBranch(child.node) && (includeHidden || !child.node.name.startsWith('.')));
  }

  /// Дочитать показанные ветви — только ради знака раскрытия.
  ///
  /// Идёт **следом за строками**, а не вместо них: чтобы ответить, надо
  /// прочитать каждый показанный каталог, и делать это до показа значило бы
  /// открывать каталог во столько раз дольше, сколько в нём подкаталогов
  /// (`docs/spec/panel-view-combined.md`, §5б).
  ///
  /// [onLearned] зовётся пачками: знаки появляются по мере того, как ответы
  /// приходят, а не все разом в конце.
  Future<void> probeBranches({
    required bool includeHidden,
    required OperationContext op,
    required void Function() onLearned,
  }) async {
    final sinceBreath = Stopwatch()..start();
    var learned = 0;

    Future<void> walk(List<_Branch> branches, int level) async {
      for (final branch in branches) {
        op.checkCanceled();
        final node = branch.node;
        // Нераскрытый архив пропускается нарочно: знак у него есть и без
        // чтения, а читать — значит открывать архив (§4б).
        final dir = node is DirectoryNode ? node : branch.mounted;
        if (dir == null) {
          continue;
        }
        if (level > 0 && !includeHidden && node.name.startsWith('.')) {
          continue;
        }
        if (branch.hasBranches == null) {
          if (sinceBreath.elapsed >= _breath) {
            sinceBreath
              ..reset()
              ..start();
            await Future<void>.delayed(Duration.zero);
            op.checkCanceled();
          }
          await _fillOne(branch);
          branch.hasBranches = _branchesIn(branch, includeHidden) ?? false;
          node.hasBranches = branch.hasBranches;
          learned++;
          // Пачками: строка с новым знаком должна появиться, пока читаются
          // остальные, — иначе дерево стоит немым до конца обхода.
          if (learned % _learnedBatch == 0) {
            onLearned();
          }
        }
        if (_expanded.contains(node.pathString)) {
          await walk(branch.children ?? const [], level + 1);
        }
      }
    }

    await walk(_roots, 0);
    if (learned % _learnedBatch != 0) {
      onLearned();
    }
  }

  /// Через сколько прочитанных ветвей показать, что узналось.
  static const int _learnedBatch = 16;

  /// Как часто обход отдаёт управление: половина кадра, как у поиска.
  static const Duration _breath = Duration(milliseconds: 8);

  /// Раскрыть ветвь. false — она и так была раскрыта.
  ///
  /// Путь принимается **любой**, даже ещё не прочитанный: раскрытое приходит
  /// путями и из настроек, и от вида, который просит показать глубокую ветвь.
  /// Чего в дереве нет, того и в строках не окажется — молча, без отказа.
  bool expand(String path) => _expanded.add(path);

  /// Свернуть ветвь. Прочитанное при этом не выбрасывается: свернули и
  /// развернули обратно — читать заново незачем.
  ///
  /// Кроме архивов: их аренду сессия со сворачиванием отпускает, и держаться
  /// за прочитанное из закрытого источника нельзя (§4б).
  bool collapse(String path) {
    final removed = _expanded.remove(path);
    if (removed) {
      _forgetMounted(path);
    }
    return removed;
  }

  bool isExpanded(String path) => _expanded.contains(path);

  /// Дочитывает раскрытые ветви — и только их.
  ///
  /// В сжатом дереве **свежее раскрытие идёт по цепочке дальше**: только что
  /// прочитанный каталог с единственным показанным подкаталогом раскрывает и
  /// его — иначе каждое раскрытие лишь склеивало бы строку, а внутрь приходилось
  /// бы заглядывать снова и снова (§4). Только прочитанное **сейчас**: что
  /// человек свернул, то само не раскрывается.
  Future<void> _fill(_Branch branch, OperationContext op, {int level = 0, required bool includeHidden}) async {
    op.checkCanceled();
    if (!_expanded.contains(branch.node.pathString)) {
      return;
    }
    // Раскрытый архив монтируется здесь: до этого он был файлом, а теперь у
    // ветви есть каталог — корень его источника (§4б).
    final node = await _directoryOf(branch);
    if (node == null) {
      return;
    }

    if (branch.children == null) {
      final List<FsNode> children;
      try {
        // Провайдер **узла**, а не корня: ветвь может уводить в другой
        // источник, и читать её должен он.
        children = await node.provider.listChildren(node);
      } on Object {
        // В ветвь не пустили — она просто останется пустой, как и в списке.
        branch.children = const [];
        return;
      }
      branch.children = [for (final child in children) _Branch(child)];
      if (compact && level > 0) {
        final shown = _shownIn(branch, level + 1, includeHidden: includeHidden);
        if (shown.length == 1 && shown.single.node is DirectoryNode) {
          _expanded.add(shown.single.node.pathString);
        }
      }
    }

    for (final child in branch.children!) {
      await _fill(child, op, level: level + 1, includeHidden: includeHidden);
    }
  }

  /// Показанные дети прочитанной ветви, стоящие на глубине [level]: без
  /// скрытого (пока его не показывают) и, если просили, без файлов.
  ///
  /// Скрытое прячется **внутри** ветвей, а корни остаются: их выбрали нарочно —
  /// это каталог панели, находки или избранное, — и прятать выбранное из-за
  /// точки в имени значило бы показать пустоту.
  List<_Branch> _shownIn(_Branch? branch, int level, {required bool includeHidden}) =>
      _shown(branch?.children ?? const [], level, includeHidden: includeHidden);

  List<_Branch> _shown(List<_Branch> branches, int level, {required bool includeHidden}) => [
    for (final branch in branches)
      if ((level == 0 || includeHidden || !branch.node.name.startsWith('.')) &&
          (!directoriesOnly || _isBranch(branch.node)))
        branch,
  ];

  /// Собирает строки: глубина и раскрытость проставляются здесь и только здесь.
  List<FsNode> _flatten(NodeListOrder order) {
    final rows = <FsNode>[];
    _heads.clear();
    _absorbed.clear();

    bool openOf(_Branch branch) =>
        (branch.node is DirectoryNode || branch.mounted != null) && _expanded.contains(branch.node.pathString);

    void walk(List<_Branch> shown, int level) {
      // Корни идут в том порядке, в каком их дали: их выбрали — человек в
      // избранном, поиск в находках, панель в обычном дереве, — и правило
      // сортировки их не переставляет. Раскладывается **содержимое** ветвей.
      if (level > 0) {
        final compare = order.compare;
        if (compare != null) {
          shown.sort((a, b) => compare(a.node, b.node));
        }
      }
      for (final top in shown) {
        var branch = top;
        // Дети строки, если их уже отобрали, проходя цепочку: второй раз
        // отбирать незачем.
        List<_Branch>? kids;
        final absorbed = <FsNode>[];

        // Цепочка: раскрытый прочитанный каталог с единственным показанным
        // подкаталогом поглощается им (§2). Корни не склеиваются — их выбрали
        // нарочно; ссылки и архивы цепочку обрывают — их сами не раскрывают.
        if (compact && level > 0) {
          while (branch.node is DirectoryNode && openOf(branch) && branch.children != null) {
            final inside = _shownIn(branch, level + 1, includeHidden: order.includeHidden);
            if (inside.length != 1 || inside.single.node is! DirectoryNode) {
              kids = inside;
              break;
            }
            absorbed.add(branch.node);
            branch = inside.single;
          }
        }

        final node = branch.node;
        final open = openOf(branch);
        node
          ..level = level
          ..isOpen = open
          // «Раскрывается» — про саму строку, и у архива оно верно всегда;
          // «есть ли внутри ветви» — про содержимое, и у архива с одними
          // файлами внутри оно ложно. Спутать их значит потерять знак
          // раскрытия ровно в тот миг, когда архив открыли (§4б).
          ..mountsAsBranch = node is! DirectoryNode && _isBranch(node)
          ..hasBranches = branch.hasBranches ?? _branchesIn(branch, order.includeHidden);
        if (absorbed.isNotEmpty) {
          // Голова — имена поглощённых по порядку: начало цепочки первым.
          _heads[node] = absorbed.map((it) => it.name).join('/');
          for (final it in absorbed) {
            _absorbed[it.pathString] = node;
          }
        }
        rows.add(node);
        if (open) {
          walk(kids ?? _shownIn(branch, level + 1, includeHidden: order.includeHidden), level + 1);
        }
      }
    }

    walk(_shown(_roots, 0, includeHidden: order.includeHidden), 0);
    return rows;
  }
}

/// Ветвь дерева: узел и то, что под ним прочитано. null — ещё не читали.
class _Branch {
  _Branch(this.node);

  final FsNode node;
  List<_Branch>? children;

  /// Корень смонтированного источника у ветви-архива; null — не открывали.
  DirectoryNode? mounted;

  /// Есть ли внутри свои ветви; null — не смотрели.
  ///
  /// Отдельно от [children]: прочитанная ветвь отвечает на этот вопрос сама, а
  /// вот дочитывать ради знака раскрытия приходится и те, что никто не
  /// раскрывал (`docs/spec/panel-view-combined.md`, §5б).
  bool? hasBranches;
}
