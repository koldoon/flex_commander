import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter/foundation.dart';

import 'search_address.dart';
import 'search_work.dart';

/// Имя колонки пути — чужое: объявляет её модуль панелей.
///
/// Ссылаться на колонку по имени можно, а зависеть ради этого от объявившего
/// её модуля — нельзя: имя это внешний контракт, он же лежит в настройках
/// (`docs/spec/column-registry.md`, §9).
const String _pathColumn = 'path';

/// Найденное — источник, смонтированный по адресу `search:/?…`.
///
/// Список принадлежит **ему одному**, а окно и панель — его зрители
/// (`docs/spec/file-search.md`, §4). Прежде владельцев было трое, и ровно на
/// стыках между ними всё и разваливалось (§4.7).
///
/// По существу это **фильтр**: проекция исходного дерева, в которой всё
/// осталось на своих местах, а лишнее отсеяно. Между корнем и находкой стоят
/// те же каталоги, в которых она лежала, — просто пустые из них не показаны.
/// Панель об этом не знает вовсе: она показывает то, что ей дали, и ходит по
/// проекции теми же клавишами, что и по обычному дереву.
///
/// Каталоги проекции — свои узлы: настоящий отдал бы всё, что в нём лежит, и
/// отобранное утонуло бы среди соседей. За каждым стоит настоящий
/// ([realPathOf]), поэтому `Alt-O` и система открывают его как обычно. А сами
/// находки — настоящие узлы своих провайдеров, поэтому копирование, удаление,
/// `F3` и `F4` работают над ними без единой правки: команда спрашивает узел, а
/// не панель.
///
/// Корень **ни в чём не лежит**: подвешенный в чужое дерево, он делал имя
/// списка звеном чужого пути — и пустое имя ломало адреса всех строк разом.
/// Выход наверх источник поэтому называет сам ([exitPath]).
class SearchProvider
    implements
        TreeProvider,
        PanelExtraColumns,
        PanelPreferredView,
        PanelNaturalOrder,
        PanelVirtualBranches,
        PanelSourceTitle,
        PanelExitPath,
        PanelFilledByWork,
        PanelSourceChanges,
        RealPathSource {
  SearchProvider(this.address, {required String title}) : sourceTitle = title {
    _root = DirectoryNode(provider: this, name: title);
  }

  /// Настоящий каталог, который показывает корень проекции: тот, в котором
  /// искали. Нужен всем, кто спрашивает «а где это на самом деле»: `Alt-O`,
  /// система, оболочка.
  String get realRootPath => address.where;

  /// Запрос целиком: по нему источник смонтирован, им же он и зовётся.
  final SearchAddress address;

  /// Как список зовут человеку. В путях не участвует — потому и волен быть
  /// любым.
  @override
  final String sourceTitle;

  late final DirectoryNode _root;

  /// Виртуальные ветви по месту внутри списка (`#/docs/deep`).
  ///
  /// Ключ — та самая метка, которую отдаёт [pathOf], а не полный адрес: у
  /// спрашивающего в руках бывает и то и другое, а место внутри у них общее.
  /// Прежде ключи хранились полными адресами, а спрашивали часть пути — и
  /// разбор не попадал никогда (§4.7).
  final Map<String, DirectoryNode> _branches = {};

  /// Дети ветвей по имени: путь ветви собирается [pathOf], и второго способа
  /// склеить его здесь нет — иначе ключи и адреса однажды разойдутся.
  final Map<DirectoryNode, Map<String, DirectoryNode>> _kids = {};

  /// Настоящий каталог за каждой ветвью.
  final Map<DirectoryNode, DirectoryNode> _mirrors = {};

  /// Что нашлось — в том порядке, в каком находилось.
  final List<FsNode> _found = [];

  List<FsNode> get found => List.unmodifiable(_found);

  /// Список прибавился: панель узнаёт об этом от источника, а не по таймеру.
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  @override
  Listenable get changes => _changes;

  bool _filled = false;

  @override
  bool get filled => _filled;

  /// Чем наполняется: та же объявленная работа, что и всегда, с доводами из
  /// адреса. Заводит её тот, кто источник открыл (`file-search.md`, §4.2), а
  /// собирается заявка одним местом на обе стороны.
  @override
  OperationSpec get work => SearchWork.specFor(address);

  /// Куда ведёт `..` — туда, где искали.
  @override
  String get exitPath => address.where;

  /// Найденное показывается деревом: плоским списком структуры не видно.
  @override
  String get preferredView => 'tree';

  /// Пути виртуальных ветвей: их дерево раскрывает сразу.
  ///
  /// Адресами строк, а не ключами словаря: панель сравнивает их со своим
  /// раскрытым, а там лежат `node.pathString`.
  @override
  Iterable<String> get openBranches => [_root.pathString, ..._branches.values.map((branch) => branch.pathString)];

  /// Добавить найденное: список растёт, пока идёт обход.
  void add(List<FsNode> found) {
    _filled = true;
    if (found.isEmpty) {
      return;
    }
    final children = <DirectoryNode, List<FsNode>>{};
    for (final node in found) {
      _found.add(node);
      children.putIfAbsent(_branchFor(node, children), () => []).add(node);
    }
    for (final entry in children.entries) {
      entry.key.nodes = [...entry.key.nodes, ...entry.value];
    }
    _changes.value++;
  }

  /// Обход начат — даже если пока ничего не нашлось.
  void markFilled() => _filled = true;

  /// Виртуальный каталог, в который ложится находка; корень — если она лежала
  /// прямо в каталоге поиска.
  DirectoryNode _branchFor(FsNode node, Map<DirectoryNode, List<FsNode>> children) {
    var branch = _root;
    for (final real in _chainOf(node)) {
      final kids = _kids.putIfAbsent(branch, () => {});
      final made = kids[real.name];
      if (made != null) {
        branch = made;
        continue;
      }
      final virtual = DirectoryNode(provider: this, name: real.name, parent: branch, modified: real.modified);
      kids[real.name] = virtual;
      _branches[_insideOf(virtual)] = virtual;
      _mirrors[virtual] = real;
      children.putIfAbsent(branch, () => []).add(virtual);
      branch = virtual;
    }
    return branch;
  }

  /// Настоящие каталоги между каталогом поиска и находкой, сверху вниз.
  ///
  /// Не дошли до каталога поиска — значит находка не из-под него (так бывает у
  /// ссылок, уводящих в сторону): она ложится в корень, а не тянет за собой
  /// цепочку до самого диска.
  List<DirectoryNode> _chainOf(FsNode node) {
    final chain = <DirectoryNode>[];
    var dir = node.parentDirectory;
    while (dir != null && dir.pathString != address.where) {
      chain.insert(0, dir);
      dir = dir.parentDirectory;
    }
    return dir == null ? const [] : chain;
  }

  @override
  String get scheme => SearchAddress.scheme;

  /// Путь узла — **адрес запроса и место внутри него**.
  ///
  /// Запрос в пути не украшение: по строке панель восстанавливает источник
  /// после перезапуска, как восстанавливает сервер по `ssh://user@host/etc`.
  /// Место внутри едет меткой (`#/Developer/lib`): у запроса свой синтаксис, и
  /// приписанный к нему путь иначе утонул бы в значении последнего довода.
  @override
  String pathOf(FsNode node) {
    if (!identical(node.provider, this)) {
      return node.pathString;
    }
    return '$_addressPath${_insideOf(node)}';
  }

  /// Место внутри списка: `#/docs/deep`; пусто — сам корень.
  String _insideOf(FsNode node) {
    final names = <String>[];
    FsNode? current = node;
    while (current != null && identical(current.provider, this) && !identical(current, _root)) {
      names.insert(0, current.name);
      current = current.parent;
    }
    return names.isEmpty ? '' : '#/${names.join('/')}';
  }

  /// Путь корня: `/?in=…&content=TODO` — то, что стоит после `search:`.
  String get _addressPath {
    final uri = address.toUri();
    return '${uri.path}?${uri.query}';
  }

  /// Настоящий путь узла: у ветви — каталог, который она показывает.
  ///
  /// У корня своего нет: он не каталог, а список, сложившийся по запросу.
  @override
  String realPathOf(FsNode node) {
    if (!identical(node.provider, this)) {
      return node.provider.capabilities.realFileSystem ? node.pathString : '';
    }
    // У корня зеркала нет — за ним стоит каталог, в котором искали.
    if (identical(node, _root)) {
      return realRootPath;
    }
    final real = _mirrors[node];
    if (real == null) {
      return '';
    }
    return real.provider.capabilities.realFileSystem ? real.pathString : '';
  }

  @override
  NodeComparator? comparatorOf(String column) => null;

  @override
  Set<String> get extraColumns => const {_pathColumn};

  @override
  DirectoryNode get rootDirectory => _root;

  @override
  String get homePath => '/';

  /// Не настоящая файловая система: путей у этого списка нет, и обещать их
  /// нельзя. Оболочке здесь не работать, панель это учтёт сама.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  /// Список уровня — как у всякого каталога: ветви и находки, лежащие здесь.
  ///
  /// Не развёрнутый в плоскую кучу весь список: панели всё равно, что
  /// показывать, и находки для неё — обычное дерево. В ветвь входят `Enter`,
  /// «..» ведёт наверх, а из корня — туда, где искали (§4а, Н3). Плоская
  /// развёртка — отдельный вид, и делать её здесь значило бы завести второе
  /// устройство одного и того же (`../roadmap.md`, Г18).
  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() => TaskOperation<ListingParams, List<FsNode>>(
    (op, params) async => [
      // У корня своего родителя нет — выход ему называет источник; у ветви
      // родитель обычный.
      if (params.dir.parentDirectory != null || (identical(params.dir, _root) && exitPath.isNotEmpty))
        ParentDirNode(params.dir),
      ...await listChildren(params.dir),
    ],
  );

  /// Все находки под этой ветвью — в порядке обхода, без ветвей между ними.
  ///
  /// Спускаемся только по **своим** ветвям: найденный каталог — настоящий узел
  /// чужого источника, и раскрывать его здесь незачем. Он сам находка.
  ///
  /// Списком панели это не служит (§4а, Н3), но нужно тому, кто спрашивает «что
  /// вообще нашлось»: счётчику, будущему плоскому виду, массовому
  /// переименованию.
  List<FsNode> flatUnder(DirectoryNode dir) {
    if (!identical(dir.provider, this)) {
      return const [];
    }
    final flat = <FsNode>[];
    void walk(DirectoryNode branch) {
      for (final node in branch.nodes) {
        if (node is DirectoryNode && identical(node.provider, this)) {
          walk(node);
          continue;
        }
        flat.add(node);
      }
    }

    walk(dir);
    return flat;
  }

  /// Содержимое ветви — только найденное. Чужой каталог свой список отдаёт сам.
  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async =>
      identical(dir.provider, this) ? dir.nodes : dir.provider.listChildren(dir);

  /// Разбор пути — по своим же ветвям; чего нет, о том и говорим «нет».
  ///
  /// Прежде промах молча возвращал корень, и любая устаревшая ветвь уводила
  /// панель в начало списка.
  @override
  Operation<String, FsNode?> resolvePath() => TaskOperation<String, FsNode?>((op, path) async => _at(path));

  /// Место внутри списка ищется по метке — и полным адресом, и одной своей
  /// частью путь называет её одинаково.
  FsNode? _at(String path) {
    final mark = path.indexOf('#');
    final inside = mark < 0 ? '' : path.substring(mark);
    if (inside.isEmpty || inside == '#/') {
      return _root;
    }
    return _branches[inside];
  }

  /// Ссылку разрешает тот, кому она принадлежит.
  @override
  Operation<LinkNode, FsNode?> resolveLink() =>
      TaskOperation<LinkNode, FsNode?>((op, link) async => link.provider.resolveLink().run(link));
}
