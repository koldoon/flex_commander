import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import '../core/listing_cache.dart';
import '../core/node_list.dart';
import '../core/tree_node_list.dart';
import '../core/selection_controller.dart';

/// Создаёт сеансы панелей.
///
/// Панелей две, и они одного типа, поэтому контейнер не может выдать «ту самую»:
/// он отдаёт фабрику, а кто именно левая, а кто правая, решает ядро.
/// Предел обхода, когда его не назвали, — тот же, что в настройках.
int _defaultConcurrency() => AppSettings.defaultSizeScanConcurrency;

class PanelSessionFactory {
  PanelSessionFactory({
    required this.registry,
    required this.editor,
    this.sizeScanConcurrency = _defaultConcurrency,
    this.naming = const ReferenceFileNaming(),
    this.cache,
    Strings? strings,
  }) : strings = strings ?? StringsRegistry();

  /// Реестр провайдеров: с какого панель начинает и чем открываются вложенные
  /// источники.
  final ProviderRegistry registry;

  /// Движок файловых операций. Он один на приложение: своего состояния у него
  /// нет, а узлы приносят своих провайдеров с собой.
  final TreeEditor editor;

  /// Размер пула обхода каталогов — общая для приложения настройка, поэтому
  /// приходит сюда, а не в [PanelSettings].
  ///
  /// Способ узнать, а не значение: настройку правят в окне, и следующий же
  /// обход должен идти по новому пределу, а не по тому, что было при запуске.
  final int Function() sizeScanConcurrency;

  /// Правило показа имени: по нему же идёт сортировка по расширению.
  final FileNaming naming;

  /// Списки уже прочитанных каталогов — один на приложение, поэтому приходит
  /// сюда, а не заводится панелью. null — кеша нет вовсе, и панель читает так
  /// же, как читала до него.
  final ListingCache? cache;

  /// Строки на языке человека: строку состояния пишет эта сторона.
  final Strings strings;

  PanelSession create(PanelSettings settings) => PanelSession(
    registry: registry,
    editor: editor,
    settings: settings,
    sizeScanConcurrency: sizeScanConcurrency,
    naming: naming,
    cache: cache,
    strings: strings,
  );
}

/// Панель со стороны ядра: каталог, список, курсор, пометка, сортировка.
///
/// Здесь живёт всё, что панель на самом деле делает: читает каталоги,
/// монтирует архивы, держит аренду, обходит размеры, помнит, где стоял курсор.
/// Экрана у этой стороны нет — вместо перерисовки сеанс говорит [onChanged], а
/// наружу отдаёт значения: [state] и [entries]
/// (`docs/spec/client-server.md`, §6).
///
/// Ничего не знает ни о второй панели, ни о виджетах: панели симметричны, а
/// связывает их ядро.
class PanelSession {
  /// [registry] — откуда панель берёт корневой источник, чем открываются
  /// вложенные (архивы) и как разбираются пути через несколько провайдеров;
  /// [editor] — движок файловых операций.
  ///
  /// Обе зависимости обязательны и приходят снаружи: какой источник корневой и
  /// каким движком выполняются операции — решение сборки приложения, а не
  /// панели. Иначе ядро знало бы конкретные реализации по именам.
  PanelSession({
    required PanelSettings settings,
    required ProviderRegistry registry,
    required TreeEditor editor,
    this.sizeScanConcurrency = _defaultConcurrency,
    this.naming = const ReferenceFileNaming(),
    this.cache,
    Strings? strings,
  }) : strings = strings ?? StringsRegistry(),
       _registry = registry,
       _editor = editor,
       _columns = settings.columns,
       _view = settings.view,
       _expanded = {...settings.expanded},
       _savedCursor = settings.cursorPath,
       _scrollOffset = settings.scroll,
       _sort = settings.sort,
       _showHidden = settings.showHidden,
       _lastPath = settings.path {
    // Прочитанное из настроек кладётся в ту же память, которой панель
    // пользуется при обычном хождении по дереву: восстановление после запуска
    // — это тот же возврат в каталог, где уже были, и отдельной ветки ему не
    // нужно.
    if (settings.path.isNotEmpty && settings.cursor.isNotEmpty) {
      _cursorMemory[settings.path] = settings.cursor;
    }
    selection.addListener(_onSelectionChanged);
  }

  /// Кто слушает перемены.
  ///
  /// Слушателей несколько: сервер рассылает события за границу, а переходник
  /// перерисовывает экран. Пока стороны в одном изоляте, они оба смотрят на
  /// один и тот же сеанс, и одним обработчиком тут не обойтись.
  final List<VoidCallback> _onChanged = [];
  final List<VoidCallback> _onListed = [];
  final List<void Function(Set<String> paths)> _onSized = [];

  /// Подписаться на перемены. Возвращает то, чем подписку снять.
  ///
  /// Три события, а не одно, и это не дробление ради дробления. Состояние без
  /// списка — десяток чисел, и разбирать, какое поле сменилось, дороже, чем
  /// отдать всё. Список — другое дело: он большой и меняется много реже. А про
  /// размеры каталогов говорится и вовсе одними путями: слать ради них список
  /// целиком значило бы возить мегабайты ради восьми байт, а везти число —
  /// везти вчерашнее.
  VoidCallback watch({VoidCallback? onChanged, VoidCallback? onListed, void Function(Set<String> paths)? onSized}) {
    if (onChanged != null) {
      _onChanged.add(onChanged);
    }
    if (onListed != null) {
      _onListed.add(onListed);
    }
    if (onSized != null) {
      _onSized.add(onSized);
    }
    return () {
      if (onChanged != null) {
        _onChanged.remove(onChanged);
      }
      if (onListed != null) {
        _onListed.remove(onListed);
      }
      if (onSized != null) {
        _onSized.remove(onSized);
      }
    };
  }

  /// Правило показа имени: по нему же идёт сортировка по расширению.
  final FileNaming naming;

  /// Списки уже прочитанных каталогов; null — читать всегда заново.
  ///
  /// Общий на обе панели: каталог, прочитанный соседкой, достаётся даром
  /// (`docs/spec/listing-cache.md`).
  final ListingCache? cache;

  /// Строки на языке человека.
  ///
  /// Вехи работы формулирует тот, кто работает, — а работает здесь эта сторона
  /// (`docs/spec/localization.md`, §5). Своих нет — значит английские, как в
  /// коде.
  final Strings strings;

  final ProviderRegistry _registry;

  /// Провайдер, содержимое которого панель показывает **сейчас**.
  ///
  /// Панель больше не привязана к одному источнику на всю жизнь: она следует
  /// за каталогом, а тот приносит своего провайдера с собой. Войти в архив —
  /// это открыть каталог чужого провайдера, и ничего кроме.
  TreeProvider get provider => _directory?.provider ?? _root;

  /// Корень, на котором стоит панель.
  ///
  /// Обычно общий (локальная ФС), но панель может встать и на свой — сервер,
  /// открытый по адресу. Тогда она его **арендатор**, и держится он, пока
  /// аренда на руках.
  TreeProvider get _root => _rootLease?.provider ?? _registry.root;

  /// Аренда своего корня; null — панель стоит на общем.
  ProviderLease? _rootLease;

  /// Адрес, которым этот корень открыт: по нему видно, что второй такой же
  /// открывать не нужно, а на другой хост — нужно.
  Uri? _ownAddress;

  /// Аренда провайдера, содержимое которого панель показывает сейчас; null —
  /// это общий корень, арендовать нечего.
  ///
  /// Одна на всю цепочку: аренда архива держит аренду того, над кем он
  /// смонтирован, — вплоть до своего корня. Поэтому панели хватает самой
  /// глубокой, а обходить стопку хозяев больше не нужно.
  ProviderLease? _lease;

  /// Сколько каталогов панель обходит одновременно, считая их размер, —
  /// настройка приложения. Настоящий предел меньше, если провайдер объявил
  /// свой: см. [_scanConcurrency].
  final int Function() sizeScanConcurrency;

  final TreeEditor _editor;

  /// Редактор дерева: движок переноса, если провайдеру есть чем работать.
  ///
  /// Сам провайдер операций не выполняет — он даёт движку примитивы
  /// ([NodeEditor]); их отсутствие и означает источник только для чтения.
  TreeEditor? get editor => provider.canWrite ? _editor : null;

  /// Сколько строк помещается в видимой части списка. Значение выставляет
  /// таблица; от него считается шаг PgUp/PgDn.
  int pageSize = 20;

  /// Тип уточнён до реализации: пометку создала панель, ей же её и закрывать
  /// ([ChangeNotifier.dispose]). Всем остальным хватает [PanelSelection] —
  /// подписка на изменения есть и в нём.
  final SelectionController selection = SelectionController();

  /// Чем набираются строки панели: сегодня — каталог, завтра дерево и находки
  /// (`docs/spec/panel-node-list.md`).
  ///
  /// Каталог живёт здесь же, а не отдельным полем: «где панель стоит» — это
  /// свойство набора строк, и второй его копии заводить нельзя, иначе они
  /// разойдутся.
  NodeList? _list;

  DirectoryNode? get _directory => _list?.directory;

  List<FsNode> _nodes = const [];

  /// Строки по путям — чтобы обход мог отдать сумму подкаталога, не перебирая
  /// весь список на каждую посчитанную ветвь.
  Map<String, FsNode>? _byPath;

  /// Строки сменились: указатель по путям пересобирается лениво.
  void _setRows(List<FsNode> rows) {
    _nodes = rows;
    _byPath = null;
  }

  FsNode? _rowAt(String path) => (_byPath ??= {for (final node in _nodes) node.pathString: node})[path];
  PanelPhase _status = PanelPhase.idle;
  FsError? _error;
  int _cursorIndex = 0;
  bool _busy = false;
  bool _active = false;
  String? _statusText;
  String? _headerText;
  String _lastPath;

  ColumnLayout _columns;
  String _view;

  /// Чем набираются строки: говорит вид, а ядро о видах не знает
  /// (`docs/spec/panel-node-list.md`, §3).
  RowsKind _rows = RowsKind.listing;

  /// Раскрытые ветви — то, что переживает и смену вида, и перезапуск.
  ///
  /// Здесь, а не только в наборе строк: набор живёт от чтения до чтения, а
  /// раскрытое человек выбирал сам, и терять его при каждом перечитывании
  /// нельзя.
  Set<String> _expanded;

  /// Раскрытое **в чужом источнике**: живёт, пока его показывают.
  ///
  /// Отдельно от [_expanded] по той же причине, что и вид: находки раскрыты
  /// потому, что иначе их не видно, а не потому, что человек их раскрывал. В
  /// настройки панели такое не пишут — иначе там осели бы `found:`-пути и
  /// цепочка предков, которую подмешивает `_listFor`.
  Set<String> _expandedHere = {};

  /// Забыть всё, что относилось к прежнему источнику.
  ///
  /// Зовётся сменой источника: просьба источника — не выбор человека, и
  /// пережить источник она не должна.
  void _forgetSourceView(TreeProvider? source) {
    final was = view;
    _viewHere = null;
    _sortHere = null;
    _expandedHere = {if (source is PanelPreferredView) ...(source as PanelPreferredView).openBranches};
    _knownBranches = {..._expandedHere};

    // Вид сменился — сменится и набор строк, который он попросит; до тех пор
    // панель показывала бы чужой. Набор при этом привязан к корню источника, и
    // с древесным она встала бы не в тот каталог.
    //
    // А вот когда вид **тот же** (дерево у человека и дерево у находок),
    // сбрасывать нельзя: вид уже стоит и второй раз ни о чём не попросит —
    // живьём находки показывались списком своего корня, из которого не
    // раскрывалась ни одна ветвь.
    final now = source is PanelPreferredView ? (source as PanelPreferredView).preferredView : _view;
    if (was != now) {
      _rows = RowsKind.listing;
    }
  }

  /// Строка, на которой стоял курсор в прошлый запуск, — путём.
  ///
  /// Одноразовая: как только строки собраны и курсор поставлен, память
  /// уступает место живому курсору.
  String _savedCursor;

  /// Насколько список промотан — то, что вид сказал в прошлый раз.
  ///
  /// Ядро об этом ничего не знает: точки приходят с той стороны, хранятся
  /// здесь и возвращаются обратно вместе с состоянием — как и имя вида.
  double _scrollOffset;
  SortSpec _sort;
  bool _showHidden;

  /// Текущая операция панели: чтение каталога или разбор пути.
  /// Хранится ради отмены, поэтому тип результата здесь не важен.
  Operation<Object?, Object?>? _operation;

  /// Номер последнего запроса чтения. Результат более старого запроса
  /// применять нельзя: пользователь уже ушёл в другой каталог.
  int _requestId = 0;

  /// Путь каталога → имя объекта под курсором. Возврат в уже посещённый
  /// каталог ставит курсор туда, где пользователь его оставил.
  final Map<String, String> _cursorMemory = {};

  /// Сколько каталогов помнить. Ограничение защищает от роста памяти при
  /// долгой работе.
  ///
  /// Между запусками переживает только одна запись — про последний каталог
  /// панели: она и лежит в настройках. Хранить всю карту значило бы копить в
  /// файле настроек список каталогов, где пользователь когда-либо был.
  static const int cursorMemoryLimit = 100;

  // --- каталог ---

  DirectoryNode? get directory => _directory;

  /// Путь показанного каталога — тем же текстом, каким его видят на экране.
  /// Куда пойдёт операция — путь под курсором (`panel-node-list.md`).
  ///
  /// Спрашивают **набор строк**: у списка каталога это сам каталог, у дерева —
  /// каталог строки под курсором. Панель тут ничего не решает: что значит «где
  /// я стою», знает тот, кто собрал строки.
  String get currentPath => _standing.isEmpty ? (_directory?.displayPath ?? '') : _standing;

  /// Каталог, в котором панель стоит с точки зрения курсора.
  ///
  /// То же, что [currentPath], только узлом: у дерева это каталог строки под
  /// курсором, а не корень источника. Спрашивают его те, кому нужен не путь, а
  /// сам каталог, — например находки, которым он становится корнем.
  DirectoryNode? get standingDirectory {
    final list = _list;
    if (list is! TreeNodeList) {
      return _directory;
    }
    return currentNode?.parentDirectory ?? _directory;
  }

  /// Где панель стоит **сейчас**: последнее, что сказал набор строк.
  ///
  /// Памятью, а не вычислением на месте: корень дерева ни в чём не лежит и
  /// каталога не называет, а панель при этом обязана остаться там, где стояла.
  String _standing = '';

  void _updateStanding() {
    final at = _list?.currentPathFor(currentNode);
    if (at != null && at.isNotEmpty) {
      _standing = at;
    }
  }

  /// Имя показанного каталога: последнее звено пути.
  String get directoryName => _directory?.name ?? '';

  /// Есть ли куда подниматься. У корня источника — нет.
  bool get canGoUp => _directory?.parentDirectory != null;

  /// Отсортированное содержимое каталога — то, что рисует таблица.
  List<FsNode> get nodes => _nodes;

  PanelPhase get status => _status;

  FsError? get error => _error;

  /// Идёт длительная операция: клавиатура игнорируется, кроме отмены.
  bool get busy => _busy;

  /// Панель активна: в ней курсор и ввод с клавиатуры.
  /// Значение выставляет [AppController], чтобы активной всегда была ровно одна.
  bool get active => _active;

  /// Текст, выставленный командой ("Loading…", сообщение об ошибке).
  /// null — строка состояния показывает объект под курсором.
  String? get statusText => _statusText;

  /// Заголовок, выставленный командой. null — показывается путь каталога.
  String? get headerText => _headerText;

  /// Вид содержимого спрашивается у провайдера: он один знает, что показывает.
  /// Обычный провайдер дерева о видах не подозревает — значит, таблица файлов.
  String get contentKind {
    final current = provider;
    return current is PanelContent ? (current as PanelContent).contentKind : SourceInfo.files;
  }

  /// Открыть каталог. Отменяет незавершённое чтение этой же панели.
  Future<void> open(DirectoryNode dir) {
    return _load(dir, cursorName: _cursorMemory[dir.pathString]);
  }

  /// Ещё одна аренда на то, в чём панель стоит сейчас; null — общий корень.
  ///
  /// Панель при этом остаётся арендатором сама: у длительной работы своя
  /// аренда, и уход панели её не касается.
  ProviderLease? leaseProvider() => _registry.leaseOf(provider);

  /// Имена в каталоге по пути — не трогая того, что показано.
  ///
  /// `listChildren`, а не `getDirectoryListing`: тот складывает список в узел и
  /// подменил бы показанное панелью, а спрашивают здесь просто имена — со
  /// скрытыми и без «..».
  ///
  /// `~` разбирает **источник**: домашний каталог у сервера свой. Ошибку не
  /// прячем — каталога нет или в него не пускают, и решать это тому, кто
  /// спросил.
  Future<List<FileEntry>> namesIn(String path) async {
    final here = provider;
    final asked = path == '~' || path == '~/' ? here.homePath : path;

    // Спрашивают двое, и спрашивают разное.
    //
    // **Строка** набирает путь руками, стоя в источнике: `/srv/da`, `~`. Такой
    // путь разбирает сам источник — у сервера и дом свой, и корень свой.
    //
    // **Вид** говорит путями строк (`FileEntry.path`), а это адреса: у всего,
    // что не местная файловая система, в них есть схема — `sftp:...`,
    // `/home/a.zip:zip:/inner`. Источнику такой адрес незнаком: он видел бы в
    // схеме имя каталога и не нашёл ничего. Дерево на сервере из-за этого не
    // показывало ни одной ветви (`docs/spec/panel-view-tree.md`, §5).
    final ResolvedNode? resolved = _isAddress(asked) ? await resolvePath().run(asked) : null;
    try {
      final node = resolved != null ? resolved.node : await here.resolvePath().run(asked);
      if (node is! DirectoryNode) {
        return const [];
      }
      // Читается тем провайдером, которому узел принадлежит, а не тем, в
      // котором стоит панель: адрес мог увести в другой источник.
      return [for (final child in await node.provider.listChildren(node)) entryOf(child)];
    } finally {
      // Аренда, взятая разбором, тут не нужна: спросили имена, а держит
      // источник живым панель, которая в нём стоит.
      await resolved?.release();
    }
  }

  /// Адрес это или путь источника.
  ///
  /// Адрес — то, у чего есть чужая схема или несколько частей: `sftp:/srv`,
  /// `/home/a.zip:zip:/inner`. Всё остальное — путь внутри источника, каким его
  /// набирает человек.
  static bool _isAddress(String path) {
    final parsed = NodePath.parse(path);
    return parsed.parts.length > 1 || parsed.scheme != NodePath.defaultScheme;
  }

  /// Разбирает путь от корня этой панели и отдаёт узел вместе с арендой.
  ///
  /// Аренду обязан отпустить тот, кто просил: путь может пройти через архив,
  /// который ради него и смонтируют. Уже открытый архив вторым экземпляром не
  /// становится — реестр отдаёт того же и просто считает арендаторов.
  Operation<String, ResolvedNode> resolvePath() => TaskOperation<String, ResolvedNode>(
    (op, path) => op.delegate(_registry.resolveDisplayPath(), ResolvePathParams(path, from: _root)),
  );

  Future<bool> openPath(String path, {bool allowConnect = true}) async {
    // Прежняя работа панели уступает место: без этого она осталась бы читать
    // впустую — номер запроса не даст применить её итог, но сама она про это
    // не знает и продолжит тянуть байты с сервера. Так же начинает и `_load`.
    _operation?.cancel();

    // Разбор пути тоже обращается к провайдеру и может быть небыстрым,
    // поэтому панель занята уже на этом шаге, а не только на чтении каталога.
    final requestId = ++_requestId;
    _busy = true;
    _status = PanelPhase.loading;
    _statusText = strings.tr('Loading…');
    _changed();

    // Одна операция на весь разбор — вместе с подключением к адресу.
    // Подключение бывает долгим (сервер на другом конце света), и всё это время
    // Esc должен работать: если операцию завести только на чтении каталога,
    // отменять во время подключения будет нечего.
    final resolving = TaskOperation<String, ResolvedNode>((op, _) async {
      // Чужая схема в начале — это другой корень: сервер, а не каталог. Панель
      // встаёт на него целиком, и разбор остатка пути идёт уже от него.
      final start = await _rootFor(op, path, allowConnect: allowConnect);
      op.checkCanceled();

      // Путь может проходить через несколько провайдеров: архив внутри архива —
      // это всё та же одна строка.
      // Разбор с вопросами о типе звена: человек набирает то, что ему
      // показали, а показанный путь схем архивов не содержит.
      final resolved = await op.delegate(_registry.resolveDisplayPath(), ResolvePathParams(path, from: start));
      op.checkCanceled();

      // Архив, набранный путём, монтируется здесь же, внутри операции: снаружи
      // прервать это было бы нечем, а лежащий на сервере архив копируется
      // целиком.
      return _asDirectory(op, resolved);
    });
    _operation = resolving;
    // Ход разбора виден в строке состояния: «Connecting to ssh://shark…»,
    // «Reading a.zip…». Без этого длинная цепочка выглядит зависанием.
    final release = _followProgress(resolving, requestId);
    // Подписка встала — можно начинать. Путь операция берёт из замыкания: он
    // нужен ей ещё и до запуска, чтобы решить, с какого корня разбирать.
    resolving.start(path);

    ResolvedNode resolved = const ResolvedNode.none();
    try {
      _error = null;
      resolved = await resolving.result;
    } on FsError catch (error) {
      // Причина нужна тому, кто просил открыть: «нет такого пути» и «такой
      // протокол мы не умеем» — разные ответы.
      _error = error;
    } on OperationCanceled {
      // Отмена во время разбора пути: панель остаётся там, где была.
      if (requestId == _requestId) {
        _status = PanelPhase.idle;
        _finish();
      }
      return false;
    } finally {
      release();
    }

    final dir = resolved.node;
    if (requestId != _requestId) {
      // Пока разбирали путь, панель уже отправили в другой каталог.
      await resolved.release();
      return false;
    }
    if (dir is! DirectoryNode) {
      // Содержимое остаётся прежним: панель меняется только после **успешного**
      // открытия. Причина неудачи уходит тому, кто просил открыть (окно ввода
      // пути), — подменять ею список файлов значило бы наказывать за опечатку
      // потерей того, на что человек смотрел.
      await resolved.release();
      _status = PanelPhase.idle;
      _finish();
      return false;
    }

    await _load(dir, lease: resolved.lease, cursorName: _cursorMemory[dir.pathString]);
    return _status != PanelPhase.error;
  }

  /// Показать каталог, **не открывая** его: курсор вида встал на объект, и
  /// каталог панели теперь тот, в котором объект лежит.
  ///
  /// Просит вид со своей навигацией — дерево (`docs/spec/panel-view-tree.md`,
  /// §3). От [openPath] отличается тремя вещами, и все три существенные:
  ///
  /// * **панель не занята** — иначе стрелка в дереве отнимала бы клавиши у
  ///   самого дерева, и каждый шаг вниз кончался бы ожиданием;
  /// * **пометка остаётся** — ушёл курсор, а не человек, и помеченное в
  ///   соседней ветви никуда не девается;
  /// * **тот же каталог не перечитывается** — курсор ходит по строкам одного
  ///   каталога чаще, чем переходит в другой.
  Future<void> follow(String directory, {String name = ''}) async {
    final here = _directory;
    if (here != null && here.pathString == directory) {
      if (name.isNotEmpty) {
        setCursorToName(name);
      }
      return;
    }

    final resolved = await resolvePath().run(directory);
    final dir = resolved.node;
    if (dir is! DirectoryNode) {
      // Каталога нет — панель остаётся там, где стояла: это ход курсора, а не
      // просьба человека, и отвечать на него пустой панелью не за что.
      await resolved.release();
      return;
    }
    await _load(dir, lease: resolved.lease, cursorName: name.isEmpty ? null : name, keepMarks: true, quiet: true);
  }

  /// Корень, от которого разбирать этот путь.
  ///
  /// Правило простое и в обе стороны одинаковое: **путь без схемы — это общий
  /// корень**, локальная ФС. Стоя на сервере, вернуться домой можно, набрав
  /// обычный путь, а остаться на нём — назвав его схему целиком. Ходьба внутри
  /// панели (Enter, «..») сюда не заходит вовсе, так что сервер от этого не
  /// «схлопывается» под ногами.
  ///
  /// Адрес чужой схемы открывает подключение, и панель **забирает его себе**:
  /// закрыть его больше некому, как и смонтированный архив. Прежний свой корень
  /// при этом закрывается — ушли с сервера, соединение разорвано. Общий корень
  /// не закрывается никогда: он не её.
  Future<TreeProvider> _rootFor(TaskOperation<Object?, Object?> op, String path, {required bool allowConnect}) async {
    final address = Uri.tryParse(path);
    if (address == null) {
      throw FsError(path, FsErrorKind.invalidAddress);
    }

    if (address.hasScheme) {
      return _rootForAddress(op, path, address, allowConnect: allowConnect);
    }

    // Без протокола это путь — и он должен быть путём: «Blah» им не является,
    // и говорить о нём «не найдено» значило бы делать вид, что мы искали.
    // Тильда считается: её разворачивает реестр в дом источника.
    if (!path.startsWith('/') && !path.startsWith('~')) {
      throw FsError(path, FsErrorKind.invalidAddress);
    }

    await _releaseRoot();
    return _registry.root;
  }

  /// Корень для строки с протоколом.
  Future<TreeProvider> _rootForAddress(
    TaskOperation<Object?, Object?> op,
    String path,
    Uri address, {
    required bool allowConnect,
  }) async {
    final scheme = address.scheme.toLowerCase();

    // Схема общего корня — это он и есть: `fs:/etc` и `/etc` значат одно.
    if (scheme == NodePath.defaultScheme || scheme == _registry.root.scheme) {
      await _releaseRoot();
      return _registry.root;
    }

    if (!_registry.knowsAddress(scheme)) {
      // Имя протокола, а не вся строка: разговор о нём, а не о пути.
      throw FsError(scheme, FsErrorKind.unsupportedScheme);
    }

    // Тот же адрес — тот же корень: перечитывать сервер заново незачем, а
    // второе подключение к нему разошлось бы состоянием с первым.
    final own = _rootLease?.provider;
    if (own != null && own.scheme == scheme && _ownAddress?.authority == address.authority) {
      return own;
    }

    if (!allowConnect) {
      // Подключаться сейчас нельзя — см. [Panel.openPath]. Отвечаем так же,
      // как о любом недоступном пути: тот, кто просил, откроет что-нибудь ещё.
      throw FsError(path, FsErrorKind.notFound);
    }

    // О себе подключение рассказывает само: панель не знает ни про этапы
    // рукопожатия, ни про то, что пароль ещё спросят.
    //
    // Сперва взять новое, потом отпустить старое: иначе панель, вернувшаяся на
    // тот же сервер другим путём, разорвала бы соединение ровно затем, чтобы
    // тут же установить его заново.
    final lease = await op.delegate(_registry.acquireAddress(), address);
    final previous = _rootLease;
    _rootLease = lease;
    _ownAddress = address;
    await previous?.release();
    return lease.provider;
  }

  /// Отпускает свой корень: панель возвращается на общий.
  Future<void> _releaseRoot() async {
    final own = _rootLease;
    _rootLease = null;
    _ownAddress = null;
    await own?.release();
  }

  /// Войти в объект под курсором.
  ///
  /// Возвращает узел, в который войти нельзя (обычный файл) — открывать его
  /// системой будет команда; null, если переход выполнен.
  Future<FsNode?> enterCurrent() async {
    final node = currentNode;
    if (node == null) {
      return null;
    }
    if (node is ParentDirNode) {
      await goUp();
      return null;
    }
    if (node is DirectoryNode) {
      await open(node);
      return null;
    }
    if (node is LinkNode) {
      final target = await _resolve(node);
      if (target is DirectoryNode) {
        await open(target);
        return null;
      }
      return _enter(target ?? node);
    }
    return _enter(node);
  }

  /// Берёт аренду на провайдера каталога, в который панель пришла, и
  /// отпускает прежнюю.
  ///
  /// [lease] — аренда, добытая по дороге (разбор пути, вход в архив); null
  /// означает «взять её самим»: в каталог соседа по тому же провайдеру или
  /// наверх, к хозяину, панель приходит без всякой аренды на руках.
  ///
  /// Сперва взять новое, потом отпустить старое: панель, идущая из архива в тот
  /// же архив уровнем выше или во вложенный, иначе закрыла бы и тут же открыла
  /// заново то, что и не переставало быть нужным, — а у 7z это ещё и
  /// перечитанное оглавление.
  void _adoptLease(ProviderLease? lease, DirectoryNode dir) {
    final previous = _lease;
    if (lease == null && identical(previous?.provider, dir.provider)) {
      // Тот же провайдер: аренда на руках и есть та самая.
      return;
    }

    // Общий корень не арендуется: он никем не смонтирован, и `leaseOf` о нём
    // ничего не знает — это и означает null.
    _lease = lease ?? _registry.leaseOf(dir.provider);
    // Отпускания не ждут: панель уже в другом каталоге, а закрытие архива —
    // уборка за ней.
    unawaited(previous?.release());
  }

  /// Вход в объект, который каталогом не является.
  ///
  /// Если такие объекты кто-то умеет открывать как дерево (архив), панель
  /// монтирует этого провайдера и заходит в его корень. Иначе объект
  /// возвращается наверх — им займётся система.
  Future<FsNode?> _enter(FsNode node) async {
    final scheme = _registry.schemeFor(node);
    if (scheme == null) {
      return node;
    }

    // Открытие может оказаться небыстрым: архив, лежащий не в локальной ФС,
    // сперва копируется во временный файл. Молчать об этом нельзя — со стороны
    // это выглядит как зависшее приложение.
    final requestId = ++_requestId;
    _busy = true;
    _status = PanelPhase.loading;
    _statusText = strings.tr('Opening {name}…', args: {'name': node.name});
    _changed();

    // Монтирование — операция, и панель держит её у себя: Esc должен прерывать
    // копирование архива с сервера, а не ждать его конца.
    final mounting = _registry.acquire();
    _operation = mounting;
    final release = _followProgress(mounting, requestId);
    mounting.start(AcquireParams(scheme, node));

    try {
      final lease = await mounting.result;
      // Аренда уходит в чтение: прочитать корень могло и не выйти — тогда
      // панель осталась там, где была, а `_load` отпустит непригодившееся.
      await _load(
        lease.provider.rootDirectory,
        lease: lease,
        cursorName: _cursorMemory[lease.provider.rootDirectory.pathString],
      );
    } on OperationCanceled {
      // Открытие прервали: панель остаётся там, где была.
      _status = PanelPhase.idle;
      _statusText = null;
    } on FsError catch (error) {
      // Битый архив — это отказ открыть, а не пустой каталог: панель остаётся
      // на месте и говорит почему.
      _error = error;
      _status = PanelPhase.error;
      _statusText = strings.describe(error);
    } finally {
      release();
      if (identical(_operation, mounting)) {
        _operation = null;
      }
      // Если открылось, состояние выставил `open`; если нет — снимаем занятость
      // здесь, иначе панель осталась бы глухой к клавиатуре.
      _busy = false;
      _changed();
    }
    return null;
  }

  /// На уровень вверх. Курсор встаёт на объект, через который сюда вошли.
  ///
  /// Если каталог открыт через ссылку, наверху нас ждёт сама ссылка, а не
  /// каталог, где физически лежит её цель: подниматься нужно туда, откуда
  /// пользователь пришёл.
  Future<void> goUp() async {
    final dir = _directory;
    if (dir == null) {
      return;
    }

    FsNode entered = dir;
    FsNode? parent = dir.parent;
    while (parent != null && parent is! DirectoryNode) {
      entered = parent;
      parent = parent.parent;
    }
    if (parent is! DirectoryNode) {
      return;
    }

    await _load(parent, cursorName: entered.name);
  }

  /// Перечитать текущий каталог, сохранив курсор и пометку.
  ///
  /// **Мимо памяти**: это ответ на «показалось не то», и показывать в ответ то
  /// же самое было бы издевательством. Запись выбрасывается, а не подменяется
  /// молча: чтение может и не выйти вовсе.
  Future<void> reload() async {
    final dir = _directory;
    if (dir == null) {
      return;
    }
    cache?.forget(dir);
    // И посчитанное тоже: перечитывание — ответ на «показалось не то».
    _forgetMeasured(dir.pathString);
    await _load(
      dir,
      cursorName: currentNode?.name,
      cursorFallbackIndex: _cursorIndex,
      keepMarks: true,
      useCache: false,
    );
  }

  /// Перечитать то же самое **тихо**: без занятости и не двигая курсор.
  ///
  /// Для растущих списков: находки прибывают, пока идёт обход, и панель должна
  /// показывать их по ходу дела, а не отнимать клавиши на каждую пачку
  /// (`docs/spec/file-search.md`, §4).
  ///
  /// Курсор возвращается **путём**: в дереве имена повторяются, и по имени он
  /// уехал бы к первой попавшейся строке.
  Future<void> refreshRows() async {
    final dir = _directory;
    if (dir == null) {
      return;
    }
    // Ветви, которых раньше не было, раскрываются сами: их назвал источник, а
    // свёрнутое человеком остаётся свёрнутым.
    final source = provider;
    if (source is PanelPreferredView) {
      final named = (source as PanelPreferredView).openBranches.toSet();
      _expandedHere.addAll(named.difference(_knownBranches));
      _knownBranches = named;
    }

    final at = currentNode?.pathString;
    await _load(dir, cursorName: currentNode?.name, keepMarks: true, useCache: false, quiet: true);
    if (at != null && _cursorToPath(at)) {
      _changed();
    }
  }

  /// Ветви, о которых источник уже говорил: новые раскрываются, о свёрнутых
  /// человеком он второй раз не просит.
  Set<String> _knownBranches = {};

  /// Прервать текущую работу панели.
  ///
  /// Внутрь отмена доходит сама: разбор пути — это операция, внутри которой
  /// идут подключение, монтирование и чтение, и каждая вложенная прерывается
  /// вместе с ней (`AsyncOperation.delegate`).
  void cancel() => _operation?.cancel();

  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String? status}) async {
    final operation = TaskOperation<void, R>((op, _) => body(op));

    // Прежняя работа уступает место, а не отказывает новой: правило то же, что
    // у чтения каталога, — последнее сказанное человеком главнее.
    _operation?.cancel();

    final requestId = ++_requestId;
    _busy = true;
    _statusText = status ?? strings.tr('Loading…');
    _operation = operation;
    // `PanelPhase` нарочно не трогается: панель не перечитывается, и список
    // файлов обязан остаться на виду — читается один файл, а не каталог.
    final release = _followProgress(operation, requestId);
    _changed();

    operation.start(null);
    try {
      return await operation.result;
    } finally {
      release();
      if (identical(_operation, operation)) {
        _operation = null;
      }
      // Занятость снимается чем бы дело ни кончилось — иначе панель осталась бы
      // глухой к клавиатуре навсегда. Но только если за это время не началась
      // работа поновее: строка состояния и занятость теперь её.
      if (requestId == _requestId) {
        _busy = false;
        _statusText = null;
      }
      _changed();
    }
  }

  /// Фокус панелям не нужен: какая область активна, знает приложение, а
  /// нажатия разбирает ранний обработчик клавиатуры.
  bool get takesKeyboard => false;

  /// Панель убрали из области: отпустить всё, что она держала.
  ///
  /// Сегодня не зовётся никем: панель пока никем не заменяют, а на выходе из
  /// приложения источники закрывает реестр — и делает это после сохранения
  /// настроек, чтобы панель успела записать свой путь. Понадобится, когда
  /// панель заменит другой вид (дерево, миниатюры): аренда источника обязана
  /// уйти вместе с той панелью, которая её брала, а не пережить её.
  ///
  /// Не ждём: отпускание может занять время (закрытие дескрипторов, обрыв
  /// соединения), а тому, кто убирает панель, ждать нечего — так же
  /// поступает и смена каталога.
  void close() {
    _operation?.cancel();
    unawaited(_releaseRoot());
    final lease = _lease;
    _lease = null;
    unawaited(lease?.release() ?? Future<void>.value());
  }

  // --- курсор ---

  int get cursorIndex => _cursorIndex;

  FsNode? get currentNode => _cursorIndex >= 0 && _cursorIndex < _nodes.length ? _nodes[_cursorIndex] : null;

  void moveCursor(int delta) => setCursorIndex(_cursorIndex + delta);

  /// Сдвинуть курсор на страницу: `direction` равен -1 или 1.
  void moveCursorPage(int direction) => moveCursor(direction * (pageSize - 1).clamp(1, pageSize));

  /// Поставить курсор на строку.
  ///
  /// [seq] — номер заявки той стороны. Зеркало двигает курсор у себя сразу,
  /// не дожидаясь ответа, а по номеру отличает свежее подтверждение от
  /// опоздавшего: иначе при удержании стрелки курсор дёргался бы назад
  /// (`docs/spec/client-server.md`, §5.5).
  void setCursorIndex(int index, {int seq = 0}) {
    if (seq != 0) {
      _cursorSeq = seq;
    }
    if (_nodes.isEmpty) {
      _setCursor(0);
      return;
    }
    _setCursor(index.clamp(0, _nodes.length - 1));
  }

  void setCursorToFirst() => setCursorIndex(0);

  void setCursorToLast() => setCursorIndex(_nodes.length - 1);

  /// Поставить курсор на объект с таким именем. Если его нет, курсор
  /// остаётся на месте.
  void setCursorToName(String name) {
    final index = _nodes.indexWhere((node) => node.name == name);
    if (index >= 0) {
      setCursorIndex(index);
    }
  }

  // --- пометка ---

  /// Инвертировать пометку объекта под курсором и сдвинуть курсор вниз —
  /// так пометка нескольких файлов подряд делается одной клавишей.
  ///
  /// [step] — шагать ли: пометка на месте курсор не двигает.
  void toggleCurrentMark({bool step = true}) {
    final node = currentNode;
    if (node == null || node is ParentDirNode) {
      return;
    }
    selection.toggle(node);
    if (step) {
      moveCursor(1);
    }
  }

  void markAll() => selection.addAll(_nodes);

  /// Помеченное, а если не помечено ничего — объект под курсором.
  ///
  /// То самое правило, по которому работают все файловые операции. Псевдоузел
  /// «..» целью не бывает: это не объект, а способ выйти наверх.
  List<FsNode> get targetNodes {
    if (selection.isNotEmpty) {
      return [
        for (final node in selection.nodes)
          if (node is! ParentDirNode) node,
      ];
    }
    final node = currentNode;
    return node == null || node is ParentDirNode ? const [] : [node];
  }

  /// Заменить пометку целиком — путями.
  ///
  /// Путями, а не порядковыми номерами: список могли перечитать, и узлы теперь
  /// другие экземпляры. Это то же самое, что делает перечитывание каталога, — и
  /// делается тем же способом.
  ///
  /// Путь, которого нет ни в каталоге, ни в прежней пометке, **разбирается**:
  /// помечают и из дерева, где видно соседние ветви, а курсор туда мог ещё не
  /// дойти — список каталога подтягивается тихо, и нажатая в тот же миг
  /// клавиша пометки не должна пропасть (`docs/spec/panel-view-tree.md`, §7).
  /// Не разобралось — объекта нет, и пометке его взять неоткуда.
  Future<void> setMarks(Set<String> paths, {int seq = 0}) {
    // Работа запоминается: пока чужой путь разбирается, о пометке уже могут
    // спросить — и клавишей, и просьбой (`docs/spec/operation-targets.md`, §3).
    final marking = _mark(paths, seq);
    _marking = marking;
    return marking.whenComplete(() {
      if (identical(_marking, marking)) {
        _marking = null;
      }
    });
  }

  /// Пометка дособралась.
  ///
  /// Ждут её те, кто берёт цели: просьбы ядром не сериализуются, и пометил
  /// ветвь в дереве — тут же нажал `F8` значило бы прочитать пометку
  /// недособранной (`docs/spec/operation-targets.md`, §3).
  ///
  /// Готового обещания здесь нарочно не лежит: `Future`, созданный при сборке
  /// панели, достаётся вместе с **зоной**, в которой его создали, и ждущий в
  /// другой зоне ждёт её оборота, а не своего. Один раз это уже стоило
  /// сорванной проверки: работа начиналась через полсекунды после клавиши. Пока
  /// разбора нет, обещание создаётся здесь и сейчас — в зоне того, кто спросил.
  Future<void> get marksSettled => _marking ?? Future<void>.value();

  /// Идущий разбор пометки; null — разбирать нечего.
  Future<void>? _marking;

  /// Номер последней применённой заявки на пометку.
  int _marksSeq = 0;

  Future<void> _mark(Set<String> paths, int seq) async {
    final known = {for (final node in _nodes) node.pathString, for (final node in selection.nodes) node.pathString};
    final strangers = <String, FsNode>{};
    for (final path in paths) {
      if (known.contains(path)) {
        continue;
      }
      try {
        final resolved = await resolvePath().run(path);
        if (resolved.node case final node?) {
          strangers[path] = node;
        }
        // Аренда отпускается сразу: пометка ничего не держит открытым — за
        // источник отвечает панель, которая в нём стоит.
        await resolved.release();
      } on FsError {
        // Объекта нет — путь просто выпадает из пометки.
      }
    }
    // Опоздавшая заявка новой не отменяет: пока эта разбирала чужой путь,
    // человек нажал ещё, и та пометка свежее.
    if (seq != 0 && seq < _marksSeq) {
      return;
    }
    // Номер ставится **вместе с пометкой**, а не при получении заявки. Иначе
    // всякое событие, случившееся за время разбора — а разбор идёт к
    // источнику, — уезжало бы с новым номером и **старой** пометкой: зеркало
    // приняло бы его за свежее подтверждение и отобрало у себя помеченное
    // (`docs/spec/client-server.md`, §5.5).
    _marksSeq = seq;
    _restoreSelection(paths, strangers: strangers);
  }

  // --- вид ---

  /// Раскладка колонок: своя у панели, но источник вправе попросить другую.
  ///
  /// Просит только тот, кто не каталог (`PanelColumns`): найденному нужна
  /// колонка пути. Настройку панели это не меняет — уйдя из находок, человек
  /// видит те же колонки, что настраивал.
  ColumnLayout get columns {
    final current = provider;
    return current is PanelColumns ? (current as PanelColumns).columns : _columns;
  }

  /// Своя раскладка колонок; чужую не трогаем.
  ///
  /// Пока источник просит собственные колонки (`PanelColumns` — список
  /// находок), на экране не панельная раскладка, а его. Записать её в
  /// настройки панели значило бы сделать выбор источника выбором человека: уйдя
  /// из находок, панель осталась бы с колонкой пути навсегда — и это не
  /// выдумка, а поймано живьём.
  void setColumnLayout(ColumnLayout layout) {
    if (provider is PanelColumns) {
      return;
    }
    _columns = layout;
    _changed();
  }

  /// Чем панель показывает каталог.
  ///
  /// Ядро об этом ничего не знает: строка приходит с той стороны, хранится
  /// здесь и возвращается обратно вместе с состоянием
  /// (`docs/spec/panel-views.md`, §7).
  ///
  /// Источник вправе попросить свой вид (`PanelPreferredView`): найденное —
  /// дерево, и плоским списком его не показать. Просьба живёт, пока его
  /// показывают, — и уход из находок возвращает вид человека сам собой, потому
  /// что вопрос задаётся каждый раз, а не запоминается. Поверх просьбы —
  /// [setView] на месте: человек волен посмотреть находки и таблицей.
  String get view {
    final current = provider;
    if (current is PanelPreferredView) {
      return _viewHere ?? (current as PanelPreferredView).preferredView;
    }
    return _view;
  }

  /// Вид, выбранный **в этом источнике**: живёт, пока его показывают.
  ///
  /// Своей настройки человек этим не меняет: он смотрит находки, а не
  /// перенастраивает панель, — то же правило, что у колонок.
  String? _viewHere;

  void setView(String value) {
    if (provider is PanelPreferredView) {
      if (_viewHere == value) {
        return;
      }
      _viewHere = value;
      _changed();
      return;
    }
    if (_view == value) {
      return;
    }
    _view = value;
    _changed();
  }

  RowsKind get rows => _rows;

  double get scrollOffset => _scrollOffset;

  /// Запомнить прокрутку. Состояние наружу не гоняется: показанное от этого не
  /// меняется, а при следующем запуске значение уедет в настройках.
  void setScrollOffset(double value) => _scrollOffset = value;

  /// Сменить набор строк: каталог или дерево.
  ///
  /// Строки пересобираются сразу: вид, попросивший дерево, обязан увидеть
  /// ветви тем же кадром, каким встал.
  Future<void> setRows(RowsKind value) async {
    if (_rows == value) {
      return;
    }
    final at = currentPath;
    final name = currentNode?.name;
    // На чём стоял курсор — **объектом**: смена вида его не двигает. Кроме
    // «..»: псевдострока показывает чужой каталог, и идти по ней в дереве
    // значило бы уводить курсор вверх, чего человек не просил.
    final was = currentNode;
    final wasPath = was == null || was is ParentDirNode ? '' : was.pathString;
    _rows = value;

    final dir = _directory;
    if (dir == null) {
      return;
    }

    if (value == RowsKind.tree) {
      _list = _listFor(dir);
      await _rebuildRows();
      // Курсор встаёт туда, где стоял в прошлый запуск; нет такой строки —
      // на то, на чём он стоял в списке; нет и её — на ветвь своего каталога:
      // иначе панель окажется на корне, в дереве длиной в весь диск.
      //
      // Именно на **том же объекте**: стояли в списке на `koldoon` — в дереве
      // стоим на нём же, а не на каталоге, в котором он лежит.
      final saved = _savedCursor;
      _savedCursor = '';
      if ((saved.isEmpty || !_cursorToPath(saved)) && (wasPath.isEmpty || !_cursorToPath(wasPath))) {
        _cursorToPath(dir.pathString);
      }
      _changed();
      return;
    }

    // Обратно в список — тем каталогом, на который **указывал курсор**, а не
    // корнем дерева. Курсор на ветви каталога значит «вот этот каталог»: в
    // дереве им и ходят, и список продолжает ход, а не пятится на уровень
    // выше. Для операций правило другое и остаётся прежним: там каталог ветви
    // — тот, в котором она лежит (`docs/spec/panel-view-tree.md`, §3).
    if (was is DirectoryNode) {
      await _load(was, keepMarks: true);
      return;
    }
    final resolved = await resolvePath().run(at);
    final target = resolved.node;
    await resolved.release();
    await _load(target is DirectoryNode ? target : dir, cursorName: name, keepMarks: true);
  }

  /// Раскрыть или свернуть ветвь по пути.
  ///
  /// Путём, а не строкой: строки живут путями, а узлы после чтения другие
  /// (`docs/spec/panel-node-list.md`, §4).
  Future<void> setExpanded(String path, {required bool expanded}) async {
    final list = _list;
    if (list is! TreeNodeList) {
      return;
    }
    final changed = expanded ? list.expand(path) : list.collapse(path);
    if (!changed) {
      return;
    }
    if (provider is PanelPreferredView) {
      _expandedHere = list.expandedPaths;
    } else {
      _expanded = list.expandedPaths;
    }
    await _rebuildRows();
  }

  /// Набор строк для этого каталога — тот, который попросил вид.
  ///
  /// У дерева корень — корень **источника**, а сам каталог раскрыт вместе со
  /// всей цепочкой до него: иначе панель показала бы дерево, в котором её
  /// самой не видно.
  NodeList _listFor(DirectoryNode dir) {
    if (_rows != RowsKind.tree) {
      return DirectoryNodeList(dir);
    }
    final previous = _list;
    // Память панели, всё, что успел раскрыть нынешний набор, и цепочка до
    // каталога — вместе. И **запоминается сразу**: иначе раскрытое цепочкой
    // живёт до первого перечитывания и молча схлопывается.
    //
    // Чьё это раскрытое — своё или источника, — решает [_openBranches]: просьбу
    // источника в настройки панели не пишут.
    // Чьё раскрытое брать, решает **этот** каталог, а не тот, что показан:
    // источник меняется раньше, чем панель успевает в него встать.
    final open = {
      ...(dir.provider is PanelPreferredView ? _expandedHere : _expanded),
      if (previous is TreeNodeList) ...previous.expandedPaths,
      for (final node in dir.path)
        if (node is DirectoryNode) node.pathString,
    };
    if (dir.provider is PanelPreferredView) {
      _expandedHere = open;
    } else {
      _expanded = open;
    }
    return TreeNodeList(roots: [dir.provider.rootDirectory], expanded: open);
  }

  /// Свести набор строк с тем, что просил вид.
  ///
  /// Чтение каталога начинается с одним набором, а пока оно идёт, вид успевает
  /// попросить другой: при запуске он встаёт как раз в это время. Живьём это
  /// выглядело так, что дерево **иногда** приходило нераскрытым и не
  /// раскрывалось вовсе — набор-то был списочный, — а лечилось повторным
  /// открытием пути.
  Future<void> _reconcileRows() async {
    final dir = _directory;
    if (dir == null) {
      return;
    }
    if ((_rows == RowsKind.tree) == (_list is TreeNodeList)) {
      return;
    }
    _list = _listFor(dir);
    await _rebuildRows();
    if (_rows == RowsKind.tree) {
      final saved = _savedCursor;
      _savedCursor = '';
      if (saved.isEmpty || !_cursorToPath(saved)) {
        _cursorToPath(dir.pathString);
      }
    }
    _changed();
  }

  /// Пересобрать строки текущим набором, ничего не читая сверх нужного.
  ///
  /// Курсор держится за **строку**, а не за место: после раскрытия ветви
  /// строки уезжают вниз, и следить надо за объектом.
  Future<void> _rebuildRows() async {
    final list = _list;
    if (list == null) {
      return;
    }
    final at = currentNode?.pathString;
    final marked = selection.paths;

    _operation?.cancel();
    final operation = list.read(order: _orderFor(list.directory.provider));
    _operation = operation;
    operation.start(null);

    final List<FsNode> rows;
    try {
      rows = await operation.result;
    } on OperationCanceled {
      return;
    } on FsError {
      return;
    }

    _setRows(List.unmodifiable(rows));
    _applyMeasured(_nodes);
    _listed();
    _restoreSelection(marked);
    if (at != null) {
      _cursorToPath(at);
    }
    _changed();
  }

  /// Ставит курсор на строку с этим путём; нет такой — оставляет как есть.
  bool _cursorToPath(String path) {
    final index = _nodes.indexWhere((node) => node.pathString == path);
    if (index < 0) {
      return false;
    }
    _cursorIndex = index;
    return true;
  }

  /// Правило раскладки — то, которым панель разложена **сейчас**.
  ///
  /// У источника со своим порядком (находки) это правило человека, пока он не
  /// щёлкнул по заголовку: щелчок живёт, пока показывают источник, и настройки
  /// панели не меняет — как и с видом, и с колонками.
  SortSpec get sort => _sortHere ?? _sort;

  /// Сортировка по колонке: та же колонка меняет направление.
  void sortBy(FsColumn column) {
    if (!column.sortable) {
      return;
    }
    sortTo(sort.toggled(column));
  }

  /// Сортировать по готовому правилу.
  ///
  /// Курсор остаётся на том же **объекте**, а не на том же месте: строка
  /// уедет, и следить надо за тем, на чём стоял курсор.
  void sortTo(SortSpec sort) {
    if (provider is PanelNaturalOrder) {
      // Порядок источника человек перебивает на месте: своей настройки он этим
      // не меняет, а уйдя из находок, увидит прежнюю.
      _sortHere = sort;
    } else {
      _sort = sort;
    }
    _measuredSinceSort = false;
    final at = currentNode?.pathString;
    final name = currentNode?.name;
    _applySort();
    // Путём, а не именем: в дереве одинаковые имена лежат в разных ветвях, и
    // курсор ушёл бы к первому попавшемуся (`docs/spec/panel-node-list.md`).
    if (at == null || !_cursorToPath(at)) {
      if (name != null) {
        setCursorToName(name);
      }
    }
    _changed();
  }

  bool get showHidden => _showHidden;

  Future<void> setShowHidden(bool value) async {
    if (_showHidden == value) {
      return;
    }
    _showHidden = value;
    _changed();
    await reload();
  }

  void setStatusText(String? text) {
    if (_statusText == text) {
      return;
    }
    _statusText = text;
    _changed();
  }

  void setHeaderText(String? text) {
    if (_headerText == text) {
      return;
    }
    _headerText = text;
    _changed();
  }

  /// Только для [AppController]: активной должна быть ровно одна панель.
  void setActive(bool value) {
    if (_active == value) {
      return;
    }
    _active = value;
    _changed();
  }

  // --- настройки ---

  /// Каталог, в котором панель оставили: с него она и начнёт.
  ///
  /// До первого чтения это то, что пришло из файла; после — тот, где она
  /// стоит. Одно поле на оба случая: восстановление после запуска — это тот же
  /// возврат в каталог, где уже были.
  String get savedPath => _directory?.pathString ?? _lastPath;

  /// Текущее состояние панели в виде сохраняемых настроек.
  PanelSettings get settings {
    final path = savedPath;
    return PanelSettings(
      // Настройки помнят **каталог**, куда панель вернётся при запуске, — и
      // это не то же, что путь под курсором.
      path: path,
      // Пока каталог не прочитан, курсора нет — но и терять запомненное
      // нельзя: настройки могут сохраниться и до первого чтения.
      cursor: currentNode?.name ?? _cursorMemory[path] ?? '',
      // Путём — ради дерева: имя там не опознаёт строку, потому что видно
      // много каталогов разом.
      cursorPath: currentNode?.pathString ?? '',
      columns: _columns,
      sort: _sort,
      showHidden: _showHidden,
      view: _view,
      expanded: _expanded.toList(),
      scroll: _scrollOffset,
    );
  }

  // --- значения для границы ---

  /// Номер списка: растёт с каждым новым.
  ///
  /// По нему та сторона отвергает заявки на строки списка, которого уже нет:
  /// пока сообщение шло, каталог могли перечитать.
  int _generation = 0;

  int get generation => _generation;

  /// Номер последней заявки на курсор, пришедшей с той стороны.
  ///
  /// Едет обратно в состоянии: по нему зеркало узнаёт своё подтверждение и
  /// отбрасывает опоздавшие.
  int _cursorSeq = 0;

  /// Состояние панели значением — всё, кроме списка.
  PanelState get state => PanelState(
    source: sourceInfo,
    currentPath: currentPath,
    directoryName: directoryName,
    shellDirectory: shellDirectory,
    canGoUp: canGoUp,
    phase: _status,
    error: _error,
    busy: _busy,
    statusText: _statusText,
    headerText: _headerText,
    cursorIndex: _cursorIndex,
    cursorSeq: _cursorSeq,
    generation: _generation,
    // Правило — показанное: в находках это то, которым человек их разложил, а
    // не то, что стоит в его настройках.
    sort: sort,
    // И применено ли оно: у источника со своим порядком (находки) строки идут
    // так, как их нашли, и каретка была бы обещанием того, чего нет.
    sorted: _order.compare != null,
    columns: columns,
    showHidden: _showHidden,
    // Показанный, а не выбранный: пока показывают находки, это их дерево
    // (`docs/spec/panel-views.md`, §7).
    view: view,
    rows: _rows,
    scroll: _scrollOffset,
    markedPaths: selection.paths,
    marksSeq: _marksSeq,
    markedSize: selection.totalSize,
    markedSizeIsFinal: selectionSizeIsFinal,
  );

  /// Список значениями — то, чем та сторона рисует таблицу.
  List<FileEntry> get entries => [for (final node in _nodes) entryOf(node)];

  /// Цели значениями — то самое, что развернёт `Targets.marked`.
  ///
  /// Тем же [targetNodes], а не своим отбором: окно, считающее по своему
  /// списку, однажды разойдётся с операцией, а по общему — не может
  /// (`docs/spec/operation-targets.md`, §3).
  List<FileEntry> get targetEntries => [for (final node in targetNodes) entryOf(node)];

  /// Каталог панели так, как его назовёт сама оболочка; пусто — выполнять
  /// здесь негде (внутри архива оболочки нет вовсе).
  String get shellDirectory {
    final current = provider;
    final here = directory;
    if (current is! ShellHost || here == null) {
      return '';
    }
    return (current as ShellHost).shellPath(here.pathString);
  }

  /// Снимок источника, в котором панель стоит сейчас.
  ///
  /// Собирается здесь, потому что только здесь есть у кого спросить. Через
  /// границу едет вместе с состоянием и меняется вместе с каталогом.
  SourceInfo get sourceInfo {
    final current = provider;
    final shell = current is ShellHost ? current as ShellHost : null;
    return SourceInfo(
      scheme: current.scheme,
      rootPath: current.rootDirectory.pathString,
      homePath: current.homePath,
      capabilities: current.capabilities,
      canWrite: current.canWrite,
      canStream: current.canStream,
      canReceive: current.canReceive,
      isShellHost: shell != null,
      contentKind: current is PanelContent ? (current as PanelContent).contentKind : SourceInfo.files,
      columns: current is PanelColumns ? (current as PanelColumns).columns : null,
      shellLabel: shell?.shellLabel ?? '',
      shellProgram: shell?.shellProgram ?? '',
    );
  }

  /// Узел значением.
  FileEntry entryOf(FsNode node) {
    final entry = entryValueOf(node);
    if (entry.size >= 0) {
      return entry;
    }
    // Растущая сумма подставляется **при чтении** и в узел не пишется: узел
    // хранит только известное окончательно. Иначе «частичное» и «настоящее»
    // становятся неразличимыми числами, и половину, застрявшую в узле, некому
    // ни отличить, ни стереть — ровно так прерванный обход и оставлял на
    // экране своё вчерашнее.
    final growing = _running[entry.path];
    return growing == null ? entry : entry.withSize(growing, isFinal: false);
  }

  /// Живой узел за строкой списка; null — такой строки в списке нет.
  ///
  /// По имени, а не по номеру: строка приезжает значением, а список за это
  /// время мог быть перечитан.
  FsNode? nodeOf(FileEntry entry) {
    for (final node in _nodes) {
      if (node.name == entry.name) {
        return node;
      }
    }
    return null;
  }

  void _changed() {
    _updateStanding();
    for (final listener in _onChanged.toList()) {
      listener();
    }
  }

  /// Каталоги, о чьём новом размере наружу ещё не сказали.
  ///
  /// Пути, а не числа: наружу едет **факт изменения**, а значение спрашивают —
  /// пока сообщение идёт, обход уходит вперёд, и увезённое число оказалось бы
  /// вчерашним.
  final Set<String> _sizeUpdates = {};

  /// У каталога появился (или пропал) размер: запомнить, чтобы отдать пачкой.
  ///
  /// Адрес — путь, а не строка списка. Строку искать бесполезно: узел у обхода
  /// свой, захваченный при старте, а список перечитывается на каждый шаг
  /// курсора по дереву — `indexOf` после первого же чтения не находит ничего,
  /// и числа переставали доходить вовсе.
  /// Число этого каталога изменилось — сказать наружу.
  ///
  /// Будит границу **само изменение**, а не тот, кто его сделал: отмена обхода
  /// — тоже изменение, а сообщение обхода, которое будило прежде, к этому мигу
  /// уже не придёт. Живьём это выглядело так: снял пометку — частичная сумма
  /// осталась висеть в строке, и «через раз», потому что иногда её уносил
  /// соседний обход.
  void _sizeChanged(String path) {
    _sizeUpdates.add(path);
    _sizeRedraw();
  }

  /// Записывает окончательный размер в строку этого пути.
  void _setSize(String path, int size) {
    final row = _rowAt(path);
    if (row is DirectoryNode) {
      row.size = size;
    }
  }

  /// Отдать накопленное: сперва числа, потом состояние.
  ///
  /// Именно в этом порядке: сумма помеченного лежит в состоянии, и приехать
  /// она должна не раньше тех размеров, из которых сложилась.
  void _flushSizes() {
    if (_sizeUpdates.isNotEmpty) {
      final paths = Set.of(_sizeUpdates);
      _sizeUpdates.clear();
      for (final listener in _onSized.toList()) {
        listener(paths);
      }
    }
    _changed();
  }

  /// Список сменился: номер вперёд, и о нём стоит рассказать.
  void _listed() {
    _generation++;
    for (final listener in _onListed.toList()) {
      listener();
    }
  }

  // --- внутреннее ---

  /// Читает каталог и применяет результат.
  ///
  /// Каталог панели меняется только после успешного чтения: иначе при отказе
  /// в доступе панель оказалась бы в каталоге, содержимое которого показать
  /// нельзя.
  Future<void> _load(
    DirectoryNode dir, {
    ProviderLease? lease,
    String? cursorName,
    int? cursorFallbackIndex,
    bool keepMarks = false,
    bool useCache = true,
    bool quiet = false,
  }) async {
    _rememberCursor();
    _operation?.cancel();
    // Сменился источник — забыли, о чём просил прежний: его вид и его
    // раскрытое пережить его не должны.
    if (!identical(dir.provider, provider)) {
      _forgetSourceView(dir.provider);
    }

    final requestId = ++_requestId;

    // Список, который панель уже видела. Он всего лишь подсказка: чтение
    // пойдёт следом в любом случае и подменит его, если каталог изменился
    // (`docs/spec/listing-cache.md`, §3).
    final list = _listFor(dir);
    final shown = useCache ? list.shown(cache, includeHidden: _showHidden) : null;
    var adopted = false;

    if (shown != null) {
      _list = list;
      _lastPath = dir.pathString;
      _adoptLease(lease, dir);
      adopted = true;
      _setRows(shown);
      _applyMeasured(_nodes);
      _applySort();
      _stopSizeScan(keepMarked: quiet);
      _restoreSelection(keepMarks ? selection.paths : null);
      _restoreCursor(cursorName, cursorFallbackIndex);
      _cursorToBranch(dir, cursorName);
      // Занятости нет: панель уже что-то показала, и отнимать у неё клавиши
      // ради чтения, которого никто не ждёт, незачем. Этим фоновое обновление
      // и отличается от `runWork`, где ждут нового экрана.
      _busy = false;
      _status = PanelPhase.idle;
      _error = null;
      _statusText = null;
      _changed();
    } else if (quiet) {
      // Каталог выставлен сразу, а список подтянется чтением: за курсором вида
      // идёт каталог, а не ожидание, и плашка обязана смениться тем же кадром,
      // что и курсор (`docs/spec/panel-view-tree.md`, §3). Занятости нет —
      // иначе стрелка в дереве отнимала бы клавиши у самого дерева.
      _list = list;
      _lastPath = dir.pathString;
      _adoptLease(lease, dir);
      adopted = true;
      _error = null;
      _changed();
    } else {
      _busy = true;
      _status = PanelPhase.loading;
      _error = null;
      _statusText = strings.tr('Loading…');
      _changed();
    }

    final operation = list.read(order: _orderFor(list.directory.provider));
    _operation = operation;
    operation.start(null);

    try {
      final nodes = await operation.result;
      if (requestId != _requestId) {
        // Пользователь уже запросил другой каталог — этот результат не нужен.
        return;
      }
      list.remember(cache, nodes, includeHidden: _showHidden);

      if (shown != null) {
        _refresh(nodes);
        return;
      }

      _list = list;
      _lastPath = dir.pathString;
      // Каталог сменился — сменилась и аренда. Делается это здесь, а не там,
      // откуда уходят: способов уйти много (открыть, подняться, набрать путь),
      // а место, где каталог сменился, одно.
      _adoptLease(lease, dir);
      adopted = true;
      _setRows(nodes);
      // До сортировки: иначе список оказался бы разложен по вчерашним числам.
      _applyMeasured(_nodes);
      _applySort();

      // Обход размеров останавливается здесь, и место у вызова несущее в обе
      // стороны. До `_restoreSelection` — потому что она уведомит пометку и
      // пересоберёт очередь уже на новых узлах; если остановить после, свежий
      // обход будет убит и заново не начнётся, ведь уведомлений больше не
      // будет. И только в этой ветке — при ошибке или отмене чтения на экране
      // остаются прежние узлы, и обход над ними по-прежнему правомерен.
      _stopSizeScan(keepMarked: quiet);
      // Пометка берётся **сейчас**, а не в миг заказа чтения: пока список шёл,
      // человек успевает пометить ещё — в дереве это обычное дело, там каталог
      // подтягивается тихо, а `Space` жмут дальше. Снимок, взятый до чтения,
      // отменял бы всё, что сделано после него.
      _restoreSelection(keepMarks ? selection.paths : null);
      _restoreCursor(cursorName, cursorFallbackIndex);
      _cursorToBranch(dir, cursorName);

      _status = PanelPhase.idle;
      _finish();
      await _reconcileRows();
    } on OperationCanceled {
      if (requestId == _requestId) {
        _status = PanelPhase.idle;
        _finish();
      }
    } on FsError catch (error) {
      if (requestId != _requestId) {
        return;
      }
      // Каталог уже на экране, и человек в нём работает: оборвавшееся соединение
      // — это сообщение в строке состояния, а не пустая панель. Запись при этом
      // выбрасывается, чтобы следующий приход не показал её опять.
      if (shown != null && error.kind != FsErrorKind.notFound) {
        cache?.forget(dir);
        _finish(statusText: strings.describe(error));
        return;
      }
      _status = PanelPhase.error;
      _error = error;
      _finish(statusText: strings.describe(error));
    } finally {
      // Аренда, добытая ради этого каталога, панели не пригодилась: читать не
      // вышло, и держать открытый архив больше некому.
      if (!adopted) {
        await lease?.release();
      }
    }
  }

  /// Показывает ход операции в строке состояния панели.
  ///
  /// Возвращает то, чем подписку снять: держать её дольше самой работы нельзя —
  /// опоздавшее событие переписало бы статус уже следующего дела. По той же
  /// причине проверяется и номер запроса.
  ///
  /// Событий бывает больше, чем имеет смысл перерисовывать: у копирования
  /// архива во временный файл они идут пачками по мере чтения байт.
  void Function() _followProgress(Operation<Object?, Object?> operation, int requestId) {
    final redraw = Throttle(_changed);
    final status = operation.status;
    void onProgress() {
      final message = status.message;
      if (requestId != _requestId || message.isEmpty || _statusText == message) {
        return;
      }
      _statusText = message;
      redraw();
    }

    status.addListener(onProgress);

    return () {
      redraw.cancel();
      status.removeListener(onProgress);
    };
  }

  void _finish({String? statusText}) {
    _busy = false;
    _statusText = statusText;
    _operation = null;
    _changed();
  }

  /// Пришло чтение того каталога, который уже показан из памяти.
  ///
  /// Курсор и пометка берутся **сейчас**, а не с показа: между ними человек
  /// успевает нажать пару стрелок, и отыгрывать их назад нельзя.
  void _refresh(List<FsNode> nodes) {
    final cursorName = currentNode?.name;
    final marked = selection.paths;
    final cursorIndex = _cursorIndex;

    _applyMeasured(nodes);
    final sorted = List<FsNode>.unmodifiable(nodes.toList()..sort(comparatorFor(_sort, naming: naming)));
    if (_sameListing(sorted)) {
      // Ничего не изменилось — и таблицу не пересобираем: иначе каждый подъём
      // наверх ронял бы её на ровном месте, а вместе с ней пометку, которая
      // живёт узлами.
      _finish();
      return;
    }

    _setRows(sorted);
    _listed();
    _stopSizeScan();
    _restoreSelection(marked);
    _restoreCursor(cursorName, cursorIndex);
    _finish();
  }

  /// Тот же ли это список, что на экране.
  ///
  /// Сравнивается видимое: имя, вид узла, время и — у файлов — размер. Размер
  /// каталога нарочно не в счёт: его дописывает обход помеченного, и у только
  /// что прочитанного узла его ещё нет.
  bool _sameListing(List<FsNode> fresh) {
    if (fresh.length != _nodes.length) {
      return false;
    }
    for (var i = 0; i < fresh.length; i++) {
      final was = _nodes[i];
      final now = fresh[i];
      if (was.name != now.name || was.runtimeType != now.runtimeType) {
        return false;
      }
      if (was is DirectoryNode) {
        continue;
      }
      if (was.size != now.size) {
        return false;
      }
      if (was is FileNode && now is FileNode && was.modified != now.modified) {
        return false;
      }
    }
    return true;
  }

  /// Чем раскладывать строки: правило панели, сравнение колонки и скрытое.
  ///
  /// У источника, отдающего узлы в своём порядке (`PanelNaturalOrder` —
  /// находки), порядок его: переставлять растущий список значило бы двигать
  /// прочитанное на экране под каждую пачку. Пока человек не попросил своего —
  /// щелчком по заголовку.
  NodeListOrder get _order => _orderFor(provider);

  /// То же для **этого** источника: чтение начинается раньше, чем панель в него
  /// встаёт, и спрашивать у показанного было бы поздно.
  NodeListOrder _orderFor(TreeProvider source) {
    if (source is PanelNaturalOrder && _sortHere == null) {
      return NodeListOrder.asGiven(includeHidden: _showHidden);
    }
    final sort = _sortHere ?? _sort;
    return NodeListOrder.of(
      sort,
      includeHidden: _showHidden,
      // Сравнение спрашивают **у источника**, а не у ядра: колонку, которой
      // ядро не знает, сортировать ему нечем (`docs/spec/panel-node-list.md`, §5).
      column: source is PanelColumns ? (source as PanelColumns).comparatorOf(sort.column) : null,
      naming: naming,
    );
  }

  /// Порядок, выбранный **в этом источнике**: живёт, пока его показывают.
  SortSpec? _sortHere;

  void _applySort() {
    // Раскладывает **набор строк**: у каталога это обычная сортировка списка, у
    // дерева — сортировка внутри ветвей. Правило одно на оба, разное только
    // применение (`docs/spec/panel-node-list.md`, §3).
    final list = _list;
    final order = _order;
    final compare = order.compare;
    final sorted =
        list == null
            ? (compare == null ? _nodes.toList() : (_nodes.toList()..sort(compare)))
            : list.reorder(_nodes, order);
    _setRows(List.unmodifiable(sorted));
    // Порядок сменился — значит сменился и список: строки те же, но их места
    // другие, а та сторона знает строки по местам.
    _listed();
  }

  /// Собрать пометку заново по путям — в том порядке, в каком их назвали.
  ///
  /// Узел каталога берётся **свежий**: после перечитывания это другой
  /// экземпляр того же объекта. Путь, которого в каталоге нет, ищется среди
  /// уже помеченного и остаётся прежним узлом: помечают и из соседних ветвей
  /// дерева, и уход курсора в другой каталог чужую пометку не трогает
  /// (`docs/spec/panel-view-tree.md`, §7). [strangers] — то, что для этого
  /// разобрал [setMarks]: путь назвали, а панель его никогда не видела. Всё
  /// остальное отбрасывается — объект исчез.
  void _restoreSelection(Set<String>? markedPaths, {Map<String, FsNode> strangers = const {}}) {
    final was = {for (final node in selection.nodes) node.pathString: node};
    if (markedPaths == null || markedPaths.isEmpty) {
      selection.clear();
      return;
    }
    final here = {for (final node in _nodes) node.pathString: node};
    final directory = _directory?.pathString;
    // Собирается **сначала**, а кладётся одним разом: пометка, меняющаяся по
    // одному объекту, на миг пуста — и этот миг видно и строке состояния, и
    // той стороне границы (`PanelSelection.replaceWith`).
    final replacement = <FsNode>[];
    for (final path in markedPaths) {
      var node = here[path];
      // Прежний узел годится, только если он **не отсюда**: объект этого
      // каталога после перечитывания обязан найтись в новом списке, а не
      // найдясь — исчез, и держать его пометкой значило бы обещать несбыточное.
      node ??= switch (was[path]) {
        final was? when was.parent?.pathString != directory => was,
        _ => null,
      };
      node ??= strangers[path];
      if (node != null) {
        replacement.add(node);
      }
    }
    selection.replaceWith(replacement);
  }

  /// Курсор ищется по имени; если объект исчез — встаёт на ближайший индекс
  /// от прежней позиции.
  /// В дереве курсор встаёт на ветвь открытого каталога — если строки с
  /// запрошенным именем в наборе нет.
  ///
  /// Иначе он оставался бы на первой строке, то есть на корне источника: уход
  /// из находок «возвращал» панель в корень диска, а не туда, откуда искали.
  void _cursorToBranch(DirectoryNode dir, String? cursorName) {
    if (_rows != RowsKind.tree) {
      return;
    }
    if (cursorName != null && currentNode?.name == cursorName) {
      return;
    }
    _cursorToPath(dir.pathString);
  }

  void _restoreCursor(String? cursorName, int? fallbackIndex) {
    if (cursorName != null) {
      final index = _nodes.indexWhere((node) => node.name == cursorName);
      if (index >= 0) {
        _cursorIndex = index;
        return;
      }
    }
    _cursorIndex = _nodes.isEmpty ? 0 : (fallbackIndex ?? 0).clamp(0, _nodes.length - 1);
  }

  void _rememberCursor() {
    final dir = _directory;
    final node = currentNode;
    if (dir == null || node == null) {
      return;
    }
    if (_cursorMemory.length >= cursorMemoryLimit) {
      _cursorMemory.remove(_cursorMemory.keys.first);
    }
    _cursorMemory[dir.pathString] = node.name;
  }

  void _setCursor(int index) {
    if (_cursorIndex == index) {
      return;
    }
    _cursorIndex = index;
    _changed();
  }

  /// Приводит разобранное к каталогу: ссылку разворачивает, архив — монтирует.
  ///
  /// Операция передаётся, а не берётся из поля: монтирование идёт **внутри**
  /// разбора пути, и прерываться должно вместе с ним.
  ///
  /// Аренда идёт с узлом: у архива, открытого здесь же, она своя, и держит она
  /// в том числе ту, с которой пришли.
  Future<ResolvedNode> _asDirectory(TaskOperation<Object?, Object?> op, ResolvedNode resolved) async {
    final node = resolved.node;
    if (node is DirectoryNode) {
      return resolved;
    }
    if (node is LinkNode) {
      final target = await _resolve(node);
      if (target is DirectoryNode) {
        return ResolvedNode(target, resolved.lease);
      }
      await resolved.release();
      return const ResolvedNode.none();
    }
    if (node == null) {
      return const ResolvedNode.none();
    }

    // Файл, который открывается как каталог, — архив, набранный путём. Так
    // замыкается круг: панель в корне архива показывает `/home/a.zip`, и эта
    // же строка обязана вернуть туда обратно. То же самое делает Enter на нём.
    final scheme = _registry.schemeFor(node);
    if (scheme == null) {
      await resolved.release();
      return const ResolvedNode.none();
    }

    final lease = await op.delegate(_registry.acquire(), AcquireParams(scheme, node));
    // Своя аренда больше не нужна: смонтированный держит её сам.
    await resolved.release();
    return ResolvedNode(lease.provider.rootDirectory, lease);
  }

  Future<FsNode?> _resolve(LinkNode link) async {
    if (link.target != null) {
      return link.target;
    }
    try {
      return await link.provider.resolveLink().run(link);
    } on FsError {
      return null;
    }
  }

  // --- размер помеченного ---

  /// Каталоги, до которых обход ещё не дошёл.
  ///
  /// У всех, кто здесь лежит, размер ещё не посчитан — это условие постановки
  /// в очередь.
  final List<DirectoryNode> _scanQueue = [];

  /// Каталоги, которые считают прямо сейчас, — не больше
  /// [sizeScanConcurrency] одновременно.
  ///
  /// Ключ — **путь**, а не узел: перечитывание каталога заменяет узлы новыми, и
  /// по узлу один и тот же каталог вставал бы в очередь второй раз, а два
  /// обхода наперегонки заканчивались бы разными числами.
  final Map<String, _SizeScan> _scans = {};

  /// Посчитанное — по путям, а не в узлах.
  ///
  /// Узлы живут до ближайшего перечитывания, в том числе тихого, за курсором
  /// дерева; посчитанное переживает их и возвращается в новые узлы
  /// ([_applyMeasured]). Иначе каждый шаг курсора по дереву стирал бы числа и
  /// запускал обход заново — размер мерцал и пересчитывался.
  ///
  /// Сюда попадает и **каждый пройденный подкаталог**: обход и так проходит
  /// через них, суммы просто перестали выбрасываться.
  final Map<String, int> _measured = {};

  /// Чьи это пути. Сменился источник — посчитанное относилось к прежнему.
  TreeProvider? _measuredFor;

  /// Забывает всё, если панель перешла в другой источник.
  void _keepMeasuredWithSource() {
    if (identical(_measuredFor, provider)) {
      return;
    }
    _measured.clear();
    _measuredFor = provider;
  }

  /// Растущие суммы идущих обходов — по корню каждого.
  ///
  /// Отдельно от [_measured]: посчитанным это станет, только когда обход дойдёт
  /// до конца. Прерванный обход своё число уносит с собой.
  final Map<String, int> _running = {};

  /// Размеры этих путей — и посчитанные, и те, что считаются прямо сейчас.
  ///
  /// Растущая сумма едет наружу наравне с итогом: в списке панели счётчик
  /// живой, и в дереве он должен быть таким же — иначе помеченная ветвь молчит
  /// прочерком, пока обход не кончится, и оживает, только если навести на неё
  /// курсор (тогда её строка попадает в список панели). Ложью это не станет:
  /// пока обход идёт, о нём спрашивают снова, а оборвался — число уходит
  /// вместе с ответом.
  ///
  /// Непосчитанного в ответе нет: прочерк в колонке рисует тот, кто спросил.
  Map<String, int> measuredSizes(Iterable<String> paths) {
    return {
      for (final path in paths)
        if (_measured[path] ?? _running[path] case final size?) path: size,
    };
  }

  /// Какие из этих путей считаются прямо сейчас: их число — половина.
  Set<String> partialSizes(Iterable<String> paths) => {
    for (final path in paths)
      if (_running.containsKey(path)) path,
  };

  /// Забывает посчитанное для каталога и всего, что под ним.
  ///
  /// Зовётся, когда человек попросил перечитать: это ответ на «показалось не
  /// то», и отвечать на него вчерашним числом было бы издевательством.
  void _forgetMeasured(String path) {
    final prefix = path.endsWith('/') ? path : '$path/';
    _measured.removeWhere((key, _) => key == path || key.startsWith(prefix));
    // И та сторона забывает: числа живут по путям и в ней тоже, а перечитали
    // как раз затем, чтобы увидеть нынешнее, а не вчерашнее.
    _sizeUpdates.addAll(_forgetting(path, prefix));
    // Сразу, а не с ближайшей пачкой: «забудь» обязано уйти **раньше** нового
    // списка, иначе та сторона на миг подставит в него вчерашние числа.
    _flushSizes();
  }

  /// Пути, о которых та сторона знает число, а мы его только что забыли.
  Iterable<String> _forgetting(String path, String prefix) sync* {
    for (final node in _nodes) {
      final key = node.pathString;
      if (node is DirectoryNode && node is! ParentDirNode && (key == path || key.startsWith(prefix))) {
        yield key;
      }
    }
  }

  /// Возвращает посчитанное в свежие узлы — до сортировки, иначе список
  /// оказался бы разложен по вчерашним числам.
  void _applyMeasured(Iterable<FsNode> nodes) {
    _keepMeasuredWithSource();
    if (_measured.isEmpty) {
      return;
    }
    for (final node in nodes) {
      // «..» размера не получает: подсчёт родителя — это подсчёт всего дерева
      // выше, и по нажатию в панели такого не ждут.
      if (node is! DirectoryNode || node is ParentDirNode) {
        continue;
      }
      // Только окончательное: растущее в узел не пишется вовсе, оно
      // подставляется при чтении ([entryOf]) из очереди обхода — единственного
      // места, которое знает, что эта сумма ещё половина.
      final size = _measured[node.pathString];
      if (size != null) {
        node.size = size;
      }
    }
  }

  /// Путь каталога уже считают или вот-вот начнут.
  bool _scanning(DirectoryNode directory) {
    final path = directory.pathString;
    return _scans.containsKey(path) || _scanQueue.any((queued) => queued.pathString == path);
  }

  /// Строка состояния обновляется не на каждый посчитанный файл.
  late final Throttle _sizeRedraw = Throttle(_flushSizes);

  /// Суммарный размер помеченных объектов.
  ///
  /// Размер файлов известен сразу, содержимое каталогов считается фоном,
  /// поэтому значение растёт по ходу обхода. Закончен ли подсчёт, говорит
  /// [selectionSizeIsFinal].
  ///
  /// Отдельного счётчика здесь нет: сумма складывается тем же правилом, каким
  /// колонка «Size» берёт своё число, — известное из узла, растущее из очереди
  /// обхода. Поэтому сумма и колонка показывают одно и то же и разойтись не
  /// могут.
  int get selectionSize {
    var total = 0;
    for (final node in selection.nodes) {
      final size = node.size > 0 ? node.size : (_running[node.pathString] ?? 0);
      if (size > 0) {
        total += size;
      }
    }
    return total;
  }

  bool get selectionSizeIsFinal => _scans.isEmpty && _scanQueue.isEmpty;

  /// Идёт общий подсчёт: считаем до конца, что бы ни делали с пометкой.
  ///
  /// Признак, а не второй список: очередь остаётся одна, меняется лишь
  /// основание, по которому в ней держат каталог.
  bool _measuringAll = false;

  /// Обход насчитал что-то, чего порядок ещё не видел.
  ///
  /// Порядок догоняет числа один раз — когда обход кончился (`_finishMeasuring`).
  bool _measuredSinceSort = false;

  /// Посчитать размеры всех каталогов текущего каталога.
  void measureDirectories() {
    _measuringAll = true;
    for (final node in _nodes) {
      // `..` пропускается: подсчёт родителя — это подсчёт всего дерева выше, и
      // по нажатию в панели такого не ждут.
      if (node is! DirectoryNode || node is ParentDirNode) {
        continue;
      }
      // Посчитанный каталог второй раз не обходим: значение авторитетно до
      // перечитывания каталога.
      if (node.size != FsNode.unknownSize || _scanning(node)) {
        continue;
      }
      _scanQueue.add(node);
    }

    _fillPool();
    _statusText = _scansRunning ? measuringStatus() : _statusText;
    _changed();
  }

  /// Что показывает строка состояния, пока идёт общий подсчёт.
  ///
  /// На медленном источнике прочерки сменяются числами не сразу, и без этой
  /// строки нажатие выглядит как «ничего не произошло».
  String measuringStatus() => strings.tr('Measuring directories…');

  bool get _scansRunning => _scans.isNotEmpty || _scanQueue.isNotEmpty;

  /// Пометка изменилась: новые каталоги встают в очередь, снятые — уходят.
  ///
  /// Идущий обход при этом не прерывается: помечать файлы продолжают по ходу
  /// подсчёта, и начинать всё заново на каждое нажатие было бы напрасной
  /// работой — до конца дело не дошло бы никогда.
  void _onSelectionChanged() {
    final selected = selection.nodes.whereType<DirectoryNode>().toSet();

    // Пока идёт общий подсчёт, пометка обход не отменяет: его попросили, и
    // снятие пометки к этой просьбе отношения не имеет.
    if (!_measuringAll) {
      // Снятое с пометки ждать в очереди перестаёт, но уже посчитанный размер
      // в узле остаётся: он всё ещё верен, и в колонке его видно.
      _scanQueue.removeWhere((directory) => !selected.contains(directory));

      final wanted = {for (final directory in selected) directory.pathString};
      for (final scan in _scans.values.toList()) {
        if (!wanted.contains(scan.directory.pathString)) {
          _cancelScan(scan.directory);
        }
      }
    }

    for (final directory in selected) {
      // Посчитанный каталог второй раз не обходим: значение авторитетно до
      // перечитывания каталога.
      if (directory.size != FsNode.unknownSize || _scanning(directory)) {
        continue;
      }
      _scanQueue.add(directory);
    }

    _fillPool();
    _changed();
  }

  /// Настоящий предел пула: меньшее из настройки приложения и того, что
  /// провайдер о себе объявил.
  ///
  /// Настройка говорит, сколько обходов сразу нужно **пользователю**;
  /// провайдер — сколько он **выдерживает**. Локальному диску десяток только
  /// на пользу, а FTP-серверу столько же обходов — способ получить отказ.
  int get _scanConcurrency => math.min(sizeScanConcurrency(), provider.capabilities.maxConcurrency);

  /// Добирает обходы из очереди, пока пул не заполнен.
  ///
  /// Обход ждёт ответа файловой системы, а не занимает процессор, поэтому
  /// несколько сразу заканчиваются заметно быстрее, чем по очереди. Предел
  /// нужен, чтобы сотня одновременных обходов не завалила диск или сервер.
  void _fillPool() {
    while (_scans.length < _scanConcurrency && _scanQueue.isNotEmpty) {
      _startScan(_scanQueue.removeAt(0));
    }
  }

  void _startScan(DirectoryNode directory) {
    final path = directory.pathString;
    // Суммы подкаталогов обход и так считает: пусть остаются, а не выбрасываются.
    final operation = sizeOperation(onDirectory: _remember);
    final scan = _SizeScan(operation, directory);
    _scans[path] = scan;

    final status = operation.status;
    void onScanned() {
      // Обход могли отменить или заменить другим, пока этот ещё рассказывает
      // о себе. Без проверки итог сменился бы частичной суммой.
      if (!identical(_scans[path], scan) || status is! MultipleTransferOperationStatus) {
        return;
      }
      // Работа сообщает о себе и когда просто начинается, а ноль в этот миг —
      // не «пусто», а «ещё ничего не насчитано»: показывать его вместо
      // прочерка значило бы мигать нулём в начале каждого обхода. Настоящий
      // ноль придёт итогом.
      if (status.itemsTransferred <= 0) {
        return;
      }
      // В узел не пишем: это половина, а узел хранит только известное.
      _running[path] = status.itemsTransferred;
      _sizeChanged(path);
    }

    status.addListener(onScanned);
    scan.stopWatching = () => status.removeListener(onScanned);
    // Очередь для того и нужна: работа создана раньше, а начинается, когда до
    // неё дошла очередь и в пуле освободилось место.
    operation.start([directory]);

    operation.result
        .then((total) => _finishScan(directory, scan, total))
        // Каталог мог исчезнуть или оказаться закрытым: засчитываем то,
        // что успели, и берём из очереди следующий.
        .catchError((Object _) => _finishScan(directory, scan, directory.size));
  }

  /// Записывает итог в узел и освобождает место в пуле.
  ///
  /// Отрицательное значение сюда попасть не должно, но зажим обязателен:
  /// [FsNode.unknownSize] в узле означает «не посчитан», и такой итог заставил
  /// бы обходить недоступный каталог заново на каждое нажатие.
  void _finishScan(DirectoryNode directory, _SizeScan scan, int total) {
    final path = directory.pathString;
    if (!identical(_scans[path], scan)) {
      // Обход отменили, а результат опоздал — он уже ни о чём.
      return;
    }

    final size = total < 0 ? 0 : total;
    _running.remove(path);
    _remember(path, size);
    // По пути: узел, с которого обход начинался, мог смениться при
    // перечитывании списка, а число нужно тому, который на экране.
    _setSize(path, size);
    _sizeChanged(path);
    _scans.remove(path);
    scan.release();
    _fillPool();
    _sizeRedraw.flush();

    if (!_scansRunning) {
      _finishMeasuring();
    }
  }

  /// Очередь опустела: подвести итог подсчёта.
  ///
  /// Сортировка по ходу обхода не пересчитывается вовсе — иначе при сортировке
  /// по размеру строки прыгали бы под курсором десятки раз в секунду. Момент
  /// один, и он здесь: обход кончился, числа окончательные.
  void _finishMeasuring() {
    final measuredAll = _measuringAll;
    if (measuredAll) {
      _measuringAll = false;
      if (_statusText == measuringStatus()) {
        _statusText = null;
      }
    }

    if (_resortMeasured() || measuredAll) {
      _changed();
    }
  }

  /// Разложить заново, если порядок стоял на размерах, которые обход изменил.
  ///
  /// Не только общий подсчёт: помеченный каталог обход проходит вместе со
  /// всеми ветвями под ним, и в дереве числа появляются сразу у многих строк.
  /// Оставить прежний порядок значило бы показать список, отсортированный по
  /// вчерашним числам (`docs/spec/directory-sizes.md`, §3).
  bool _resortMeasured() {
    if (!_measuredSinceSort) {
      return false;
    }
    _measuredSinceSort = false;
    if (_sort.column != FsColumn.size) {
      return false;
    }

    // Курсор держится за **объект**, а не за место: строка уедет, и следить
    // надо за тем, на чём стоял курсор. Путём, а не именем: в дереве
    // одинаковые имена лежат в разных ветвях.
    final at = currentNode?.pathString;
    final name = currentNode?.name;
    _applySort();
    if (at == null || !_cursorToPath(at)) {
      if (name != null) {
        setCursorToName(name);
      }
    }
    return true;
  }

  /// Запоминает окончательную сумму каталога.
  ///
  /// Только окончательную: частичная, застывшая как итог, — ложь, и обход
  /// рассказывает о каталоге лишь тогда, когда прошёл его целиком.
  void _remember(String path, int bytes) {
    _keepMeasuredWithSource();
    _measured[path] = bytes;
    _measuredSinceSort = true;

    // Обход проходит через подкаталоги и суммы по ним считает по дороге —
    // отдать их строке ничего не стоит, а без этого дерево показывало число
    // только у той ветви, которую пометили (`docs/spec/directory-sizes.md`).
    final row = _rowAt(path);
    if (row is DirectoryNode && row.size != bytes) {
      row.size = bytes;
      _sizeChanged(path);
    }
  }

  /// Прекращает обход одного каталога, не трогая ни остальные, ни очередь.
  void _cancelScan(DirectoryNode directory) {
    final path = directory.pathString;
    final scan = _scans.remove(path);
    if (scan == null) {
      return;
    }
    // Растущая сумма уходит вместе с обходом, и стирать её больше негде: в
    // узлах её нет, она жила здесь. Частичная сумма, застывшая в колонке как
    // итог, — ложь.
    _running.remove(path);
    scan.cancel();
    _sizeChanged(path);
  }

  /// Забывает и идущие обходы, и очередь.
  ///
  /// Очередь чистится без сброса размеров: в неё попадают только каталоги
  /// с непосчитанным размером, сбрасывать там нечего.
  ///
  /// [keepMarked] — тихое чтение за курсором дерева: помеченное **продолжает
  /// считаться**. Дерево водит панель по ветвям, и каждый шаг курсора менял бы
  /// каталог; обрывая на нём обход, панель начинала бы счёт заново — а чаще не
  /// начинала вовсе: пометка при этом не меняется, а без её уведомления никто
  /// не поставит каталог в очередь снова. Помеченное живёт узлами, которые
  /// пережили чтение, поэтому обход над ними по-прежнему правомерен.
  void _stopSizeScan({bool keepMarked = false, bool notify = true}) {
    final marked = keepMarked ? selection.paths : const <String>{};
    for (final scan in _scans.values.toList()) {
      if (marked.contains(scan.directory.pathString)) {
        continue;
      }
      _cancelScan(scan.directory);
    }
    _scanQueue.removeWhere((directory) => !marked.contains(directory.pathString));
    // Не `cancel`: в очереди уведомлений лежат «забудь» от только что
    // отменённых обходов, и бросить их значило бы оставить их частичные суммы
    // висеть на экране навсегда. Кроме закрытия панели — там некому и слушать.
    if (notify) {
      _sizeRedraw.flush();
    } else {
      _sizeRedraw.cancel();
    }
    // Уход из каталога подсчёт прекращает: считать то, на что уже не смотрят,
    // незачем.
    if (_scansRunning) {
      // Что-то помеченное считается дальше — общий подсчёт при этом всё равно
      // кончился: его просили для **того** каталога, из которого ушли.
      _measuringAll = false;
      return;
    }
    _measuringAll = false;
    if (_statusText == measuringStatus()) {
      _statusText = null;
    }
  }

  void dispose() {
    _operation?.cancel();
    _stopSizeScan(notify: false);
    // Панель ушла — она больше не арендатор ни архива, ни своего сервера.
    // Закроются они, только если держать их больше некому: работа, ушедшая в
    // фон, продолжает читать то, из чего панель уже вышла.
    unawaited(_lease?.release());
    _lease = null;
    unawaited(_releaseRoot());
    selection.removeListener(_onSelectionChanged);
    selection.dispose();
    _onChanged.clear();
    _onListed.clear();
    _onSized.clear();
  }
}

/// Один идущий обход каталога: сама операция и подписка на её сообщения.
class _SizeScan {
  _SizeScan(this.operation, this.directory);

  final Operation<List<FsNode>, int> operation;

  /// Узел, с которого обход начат: по нему находят строку в списке.
  final DirectoryNode directory;

  /// Чем прекратить слушать ход обхода; null — уже прекратили.
  void Function()? stopWatching;

  void release() {
    stopWatching?.call();
    stopWatching = null;
  }

  void cancel() {
    operation.cancel();
    release();
  }
}
