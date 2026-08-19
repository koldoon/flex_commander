import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'selection_controller.dart';

export 'package:fc_api/fc_api.dart' show Panel, PanelStatus;

/// Создаёт панели.
///
/// Панелей две, и они одного типа, поэтому контейнер не может выдать «ту самую»:
/// он отдаёт фабрику, а кто именно левая, а кто правая, решает [AppController].
class PanelControllerFactory {
  PanelControllerFactory({
    required this.registry,
    required this.editor,
    this.sizeScanConcurrency = AppSettings.defaultSizeScanConcurrency,
  });

  /// Реестр провайдеров: с какого панель начинает и чем открываются вложенные
  /// источники.
  final ProviderRegistry registry;

  /// Движок файловых операций. Он один на приложение: своего состояния у него
  /// нет, а узлы приносят своих провайдеров с собой.
  final TreeEditor editor;

  /// Размер пула обхода каталогов — общая для приложения настройка, поэтому
  /// приходит сюда, а не в [PanelSettings].
  final int sizeScanConcurrency;

  PanelController create(PanelSettings settings) =>
      PanelController(registry: registry, editor: editor, settings: settings, sizeScanConcurrency: sizeScanConcurrency);
}

/// Состояние одной панели — реализация [Panel].
///
/// Ничего не знает ни о второй панели, ни о виджетах: панели симметричны, а
/// связывает их `AppController`. Наружу панель видна только как [Panel] —
/// включая подписку на изменения: [Panel] сам по себе [Listenable], и виджету
/// ядра или содержимому от модуля реализация не нужна.
class PanelController extends ChangeNotifier implements Panel {
  /// [registry] — откуда панель берёт корневой источник, чем открываются
  /// вложенные (архивы) и как разбираются пути через несколько провайдеров;
  /// [editor] — движок файловых операций.
  ///
  /// Обе зависимости обязательны и приходят снаружи: какой источник корневой и
  /// каким движком выполняются операции — решение сборки приложения, а не
  /// панели. Иначе ядро знало бы конкретные реализации по именам.
  PanelController({
    required PanelSettings settings,
    required ProviderRegistry registry,
    required TreeEditor editor,
    this.sizeScanConcurrency = AppSettings.defaultSizeScanConcurrency,
  }) : _registry = registry,
       _editor = editor,
       _columns = settings.columns,
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

  final ProviderRegistry _registry;

  /// Провайдер, содержимое которого панель показывает **сейчас**.
  ///
  /// Панель больше не привязана к одному источнику на всю жизнь: она следует
  /// за каталогом, а тот приносит своего провайдера с собой. Войти в архив —
  /// это открыть каталог чужого провайдера, и ничего кроме.
  @override
  TreeProvider get provider => _directory?.provider ?? _root;

  /// Корень, на котором стоит панель.
  ///
  /// Обычно общий (локальная ФС), но панель может встать и на свой — сервер,
  /// открытый по адресу. Тогда он принадлежит ей: закрыть его больше некому.
  TreeProvider get _root => _ownRoot ?? _registry.root;

  /// Корень, который панель открыла сама; null — стоит на общем.
  TreeProvider? _ownRoot;

  /// Адрес, которым этот корень открыт: по нему видно, что второй такой же
  /// открывать не нужно, а на другой хост — нужно.
  Uri? _ownAddress;

  /// Сколько каталогов панель обходит одновременно, считая их размер, —
  /// настройка приложения. Настоящий предел меньше, если провайдер объявил
  /// свой: см. [_scanConcurrency].
  final int sizeScanConcurrency;

  final TreeEditor _editor;

  /// Редактор дерева: движок переноса, если провайдеру есть чем работать.
  ///
  /// Сам провайдер операций не выполняет — он даёт движку примитивы
  /// ([NodeEditor]); их отсутствие и означает источник только для чтения.
  @override
  TreeEditor? get editor => provider.canWrite ? _editor : null;

  /// Сколько строк помещается в видимой части списка. Значение выставляет
  /// таблица; от него считается шаг PgUp/PgDn.
  @override
  int pageSize = 20;

  /// Тип уточнён до реализации: пометку создала панель, ей же её и закрывать
  /// ([ChangeNotifier.dispose]). Всем остальным хватает [PanelSelection] —
  /// подписка на изменения есть и в нём.
  @override
  final SelectionController selection = SelectionController();

  DirectoryNode? _directory;
  List<FsNode> _nodes = const [];
  PanelStatus _status = PanelStatus.idle;
  FsError? _error;
  int _cursorIndex = 0;
  bool _busy = false;
  bool _active = false;
  String? _statusText;
  String? _headerText;
  String _lastPath;

  ColumnLayout _columns;
  SortSpec _sort;
  bool _showHidden;

  /// Текущая операция панели: чтение каталога или разбор пути.
  /// Хранится ради отмены, поэтому тип результата здесь не важен.
  AsyncOperation<Object?>? _operation;

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

  @override
  DirectoryNode? get directory => _directory;

  /// Отсортированное содержимое каталога — то, что рисует таблица.
  @override
  List<FsNode> get nodes => _nodes;

  @override
  PanelStatus get status => _status;

  @override
  FsError? get error => _error;

  /// Идёт длительная операция: клавиатура игнорируется, кроме отмены.
  @override
  bool get busy => _busy;

  /// Панель активна: в ней курсор и ввод с клавиатуры.
  /// Значение выставляет [AppController], чтобы активной всегда была ровно одна.
  @override
  bool get active => _active;

  /// Текст, выставленный командой ("Loading…", сообщение об ошибке).
  /// null — строка состояния показывает объект под курсором.
  @override
  String? get statusText => _statusText;

  /// Заголовок, выставленный командой. null — показывается путь каталога.
  @override
  String? get headerText => _headerText;

  /// Вид содержимого спрашивается у провайдера: он один знает, что показывает.
  /// Обычный провайдер дерева о видах не подозревает — значит, таблица файлов.
  @override
  String get contentKind {
    final current = provider;
    return current is PanelContent ? (current as PanelContent).contentKind : PanelViewports.files;
  }

  /// Открыть каталог. Отменяет незавершённое чтение этой же панели.
  @override
  Future<void> open(DirectoryNode dir) {
    return _load(dir, cursorName: _cursorMemory[dir.pathString]);
  }

  /// Открыть каталог по строке пути. Возвращает false, если путь недоступен
  /// или это не каталог — тогда вызывающий код решает, куда открыть панель.
  /// Разбирает путь, переиспользуя то, что панель уже смонтировала.
  ///
  /// Иначе путь внутрь открытого архива поднял бы второй экземпляр провайдера
  /// поверх того же файла: записанное через него панель бы не увидела — её
  /// оглавление принадлежит первому.
  @override
  AsyncOperation<FsNode?> resolvePath(String path) =>
      _registry.resolveDisplayPath(path, from: _root, reuse: _mountedProviders);

  /// Цепочка провайдеров, на которой стоит панель: от текущего к корню.
  Iterable<TreeProvider> get _mountedProviders sync* {
    for (TreeProvider? current = _directory?.provider; current != null; current = _hostProviderOf(current)) {
      yield current;
    }
  }

  @override
  Future<bool> openPath(String path) async {
    // Разбор пути тоже обращается к провайдеру и может быть небыстрым,
    // поэтому панель занята уже на этом шаге, а не только на чтении каталога.
    final requestId = ++_requestId;
    _busy = true;
    _status = PanelStatus.loading;
    _statusText = 'Loading…';
    notifyListeners();

    // Одна операция на весь разбор — вместе с подключением к адресу.
    // Подключение бывает долгим (сервер на другом конце света), и всё это время
    // Esc должен работать: если операцию завести только на чтении каталога,
    // отменять во время подключения будет нечего.
    final resolving = TaskOperation<FsNode?>((op) async {
      // Чужая схема в начале — это другой корень: сервер, а не каталог. Панель
      // встаёт на него целиком, и разбор остатка пути идёт уже от него.
      final start = await _rootFor(path);
      op.checkCanceled();

      // Путь может проходить через несколько провайдеров: архив внутри архива —
      // это всё та же одна строка.
      // Разбор с вопросами о типе звена: человек набирает то, что ему
      // показали, а показанный путь схем архивов не содержит.
      final inner = _registry.resolveDisplayPath(path, from: start, reuse: _mountedProviders);
      _innerOperation = inner;
      try {
        return await inner.result;
      } finally {
        _innerOperation = null;
      }
    });
    _operation = resolving;

    DirectoryNode? dir;
    try {
      _error = null;
      dir = await _asDirectory(await resolving.result);
    } on FsError catch (error) {
      // Причина нужна тому, кто просил открыть: «нет такого пути» и «такой
      // протокол мы не умеем» — разные ответы.
      _error = error;
      dir = null;
    } on OperationCanceled {
      // Отмена во время разбора пути: панель остаётся там, где была.
      if (requestId == _requestId) {
        _status = PanelStatus.idle;
        _finish();
      }
      return false;
    }

    if (requestId != _requestId) {
      // Пока разбирали путь, панель уже отправили в другой каталог.
      return false;
    }
    if (dir == null) {
      // Содержимое остаётся прежним: панель меняется только после **успешного**
      // открытия. Причина неудачи уходит тому, кто просил открыть (окно ввода
      // пути), — подменять ею список файлов значило бы наказывать за опечатку
      // потерей того, на что человек смотрел.
      _status = PanelStatus.idle;
      _finish();
      return false;
    }

    await _load(dir, cursorName: _cursorMemory[dir.pathString]);
    return _status != PanelStatus.error;
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
  Future<TreeProvider> _rootFor(String path) async {
    final address = Uri.tryParse(path);
    if (address == null) {
      throw FsError(path, FsErrorKind.invalidAddress);
    }

    if (address.hasScheme) {
      return _rootForAddress(path, address);
    }

    // Без протокола это путь — и он должен быть путём: «Blah» им не является,
    // и говорить о нём «не найдено» значило бы делать вид, что мы искали.
    // Тильда считается: её разворачивает реестр в дом источника.
    if (!path.startsWith('/') && !path.startsWith('~')) {
      throw FsError(path, FsErrorKind.invalidAddress);
    }

    await _releaseOwnRoot();
    return _registry.root;
  }

  /// Корень для строки с протоколом.
  Future<TreeProvider> _rootForAddress(String path, Uri address) async {
    final scheme = address.scheme.toLowerCase();

    // Схема общего корня — это он и есть: `fs:/etc` и `/etc` значат одно.
    if (scheme == NodePath.defaultScheme || scheme == _registry.root.scheme) {
      await _releaseOwnRoot();
      return _registry.root;
    }

    if (!_registry.knowsAddress(scheme)) {
      // Имя протокола, а не вся строка: разговор о нём, а не о пути.
      throw FsError(scheme, FsErrorKind.unsupportedScheme);
    }

    // Тот же адрес — тот же корень: перечитывать сервер заново незачем, а
    // второе подключение к нему разошлось бы состоянием с первым.
    final own = _ownRoot;
    if (own != null && own.scheme == scheme && _ownAddress?.authority == address.authority) {
      return own;
    }

    final opened = await _registry.openAddress(address);
    await _releaseOwnRoot();
    _ownRoot = opened;
    _ownAddress = address;
    return opened;
  }

  /// Закрывает корень, открытый самой панелью.
  Future<void> _releaseOwnRoot() async {
    final own = _ownRoot;
    _ownRoot = null;
    _ownAddress = null;
    if (own != null) {
      await ProviderRegistry.disposeProvider(own);
    }
  }

  /// Войти в объект под курсором.
  ///
  /// Возвращает узел, в который войти нельзя (обычный файл) — открывать его
  /// системой будет команда; null, если переход выполнен.
  @override
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

  /// Отпускает провайдеров, из которых панель ушла, — всю цепочку.
  ///
  /// Уходят не из одного провайдера, а из стопки: архив внутри архива держится
  /// на файле внешнего, и, выйдя из обоих сразу (набрали путь, ушли в корень),
  /// закрыть надо оба. Поэтому цепочка обходится по хозяевам: корень
  /// смонтированного провайдера — это узел того, над кем он стоит.
  ///
  /// Провайдеры, на которых держится тот, куда пришли, не трогаются: войдя в
  /// архив **внутри** архива, внешний закрывать нельзя — на нём стоит
  /// внутренний. Корень реестра не трогается никогда: он один на приложение и
  /// панели не принадлежит.
  ///
  /// Правило верно, пока окно операции модально: уйти из каталога, из которого
  /// идёт копирование, сейчас нельзя. Когда операции начнут работать в фоне
  /// (`AsyncCommand`), провайдера придётся отпускать по счётчику пользователей,
  /// а не по уходу панели.
  void _releaseProvider(TreeProvider? provider, {required TreeProvider keeping}) {
    final kept = <TreeProvider>{_registry.root};
    for (TreeProvider? current = keeping; current != null; current = _hostProviderOf(current)) {
      kept.add(current);
    }

    var current = provider;
    while (current != null && !kept.contains(current)) {
      final host = _hostProviderOf(current);
      unawaited(ProviderRegistry.disposeProvider(current));
      current = host;
    }
  }

  /// Провайдер, над которым смонтирован этот; null — он сам себе корень.
  TreeProvider? _hostProviderOf(TreeProvider provider) => provider.rootDirectory.parent?.provider;

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
    _busy = true;
    _status = PanelStatus.loading;
    _statusText = 'Opening ${node.name}…';
    notifyListeners();

    try {
      final mounted = await _registry.mount(scheme, node);
      await open(mounted.rootDirectory);
      // Прочитать корень могло и не выйти: тогда панель осталась там, где была,
      // а смонтированное держит открытый файл впустую.
      _releaseProvider(mounted, keeping: provider);
    } on FsError catch (error) {
      // Битый архив — это отказ открыть, а не пустой каталог: панель остаётся
      // на месте и говорит почему.
      _error = error;
      _status = PanelStatus.error;
      _statusText = error.message;
    } finally {
      // Если открылось, состояние выставил `open`; если нет — снимаем занятость
      // здесь, иначе панель осталась бы глухой к клавиатуре.
      _busy = false;
      notifyListeners();
    }
    return null;
  }

  /// На уровень вверх. Курсор встаёт на объект, через который сюда вошли.
  ///
  /// Если каталог открыт через ссылку, наверху нас ждёт сама ссылка, а не
  /// каталог, где физически лежит её цель: подниматься нужно туда, откуда
  /// пользователь пришёл.
  @override
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
  @override
  Future<void> reload() async {
    final dir = _directory;
    if (dir == null) {
      return;
    }
    await _load(dir, cursorName: currentNode?.name, cursorFallbackIndex: _cursorIndex, markedNames: selection.names);
  }

  /// Прервать текущее чтение.
  ///
  /// Отмена доходит и внутрь: разбор пути — это внешняя операция (подключение
  /// плюс чтение), а каталог читает вложенная, и остановить нужно ту, что идёт
  /// прямо сейчас.
  @override
  void cancel() {
    _operation?.cancel();
    _innerOperation?.cancel();
  }

  /// Вложенная операция разбора пути, пока она идёт.
  AsyncOperation<Object?>? _innerOperation;

  // --- курсор ---

  @override
  int get cursorIndex => _cursorIndex;

  @override
  FsNode? get currentNode => _cursorIndex >= 0 && _cursorIndex < _nodes.length ? _nodes[_cursorIndex] : null;

  @override
  void moveCursor(int delta) => setCursorIndex(_cursorIndex + delta);

  /// Сдвинуть курсор на страницу: `direction` равен -1 или 1.
  @override
  void moveCursorPage(int direction) => moveCursor(direction * (pageSize - 1).clamp(1, pageSize));

  @override
  void setCursorIndex(int index) {
    if (_nodes.isEmpty) {
      _setCursor(0);
      return;
    }
    _setCursor(index.clamp(0, _nodes.length - 1));
  }

  @override
  void setCursorToFirst() => setCursorIndex(0);

  @override
  void setCursorToLast() => setCursorIndex(_nodes.length - 1);

  /// Поставить курсор на объект с таким именем. Если его нет, курсор
  /// остаётся на месте.
  @override
  void setCursorToName(String name) {
    final index = _nodes.indexWhere((node) => node.name == name);
    if (index >= 0) {
      setCursorIndex(index);
    }
  }

  // --- пометка ---

  /// Инвертировать пометку объекта под курсором и сдвинуть курсор вниз —
  /// так пометка нескольких файлов подряд делается одной клавишей.
  @override
  void toggleCurrentMark() {
    final node = currentNode;
    if (node == null || node is ParentDirNode) {
      return;
    }
    selection.toggle(node);
    moveCursor(1);
  }

  @override
  void markAll() => selection.addAll(_nodes);

  // --- вид ---

  @override
  ColumnLayout get columns => _columns;

  @override
  void setColumnLayout(ColumnLayout layout) {
    _columns = layout;
    notifyListeners();
  }

  @override
  SortSpec get sort => _sort;

  /// Сортировка по колонке: та же колонка меняет направление.
  /// Курсор остаётся на том же объекте, а не на том же индексе.
  @override
  void sortBy(FsColumn column) {
    if (!column.sortable) {
      return;
    }
    _sort = _sort.toggled(column);
    final name = currentNode?.name;
    _applySort();
    if (name != null) {
      setCursorToName(name);
    }
    notifyListeners();
  }

  @override
  bool get showHidden => _showHidden;

  @override
  Future<void> setShowHidden(bool value) async {
    if (_showHidden == value) {
      return;
    }
    _showHidden = value;
    notifyListeners();
    await reload();
  }

  @override
  void setStatusText(String? text) {
    if (_statusText == text) {
      return;
    }
    _statusText = text;
    notifyListeners();
  }

  @override
  void setHeaderText(String? text) {
    if (_headerText == text) {
      return;
    }
    _headerText = text;
    notifyListeners();
  }

  /// Только для [AppController]: активной должна быть ровно одна панель.
  void setActive(bool value) {
    if (_active == value) {
      return;
    }
    _active = value;
    notifyListeners();
  }

  // --- настройки ---

  /// Текущее состояние панели в виде сохраняемых настроек.
  @override
  PanelSettings get settings {
    final path = _directory?.pathString ?? _lastPath;
    return PanelSettings(
      path: path,
      // Пока каталог не прочитан, курсора нет — но и терять запомненное
      // нельзя: настройки могут сохраниться и до первого чтения.
      cursor: currentNode?.name ?? _cursorMemory[path] ?? '',
      columns: _columns,
      sort: _sort,
      showHidden: _showHidden,
    );
  }

  // --- внутреннее ---

  /// Читает каталог и применяет результат.
  ///
  /// Каталог панели меняется только после успешного чтения: иначе при отказе
  /// в доступе панель оказалась бы в каталоге, содержимое которого показать
  /// нельзя.
  Future<void> _load(
    DirectoryNode dir, {
    String? cursorName,
    int? cursorFallbackIndex,
    Set<String>? markedNames,
  }) async {
    _rememberCursor();
    _operation?.cancel();

    final requestId = ++_requestId;
    _busy = true;
    _status = PanelStatus.loading;
    _error = null;
    _statusText = 'Loading…';
    notifyListeners();

    final operation = dir.provider.getDirectoryListing(dir, includeHidden: _showHidden);
    _operation = operation;

    try {
      final nodes = await operation.result;
      if (requestId != _requestId) {
        // Пользователь уже запросил другой каталог — этот результат не нужен.
        return;
      }

      final left = _directory?.provider;
      _directory = dir;
      _lastPath = dir.pathString;
      // Из смонтированного провайдера ушли — закрыть его файлы и соединения.
      // Делается это здесь, а не там, откуда уходят: способов уйти много
      // (открыть, подняться, набрать путь), а место, где каталог сменился, одно.
      _releaseProvider(left, keeping: dir.provider);
      _nodes = nodes;
      _applySort();

      // Обход размеров останавливается здесь, и место у вызова несущее в обе
      // стороны. До `_restoreSelection` — потому что она уведомит пометку и
      // пересоберёт очередь уже на новых узлах; если остановить после, свежий
      // обход будет убит и заново не начнётся, ведь уведомлений больше не
      // будет. И только в этой ветке — при ошибке или отмене чтения на экране
      // остаются прежние узлы, и обход над ними по-прежнему правомерен.
      _stopSizeScan();
      _restoreSelection(markedNames);
      _restoreCursor(cursorName, cursorFallbackIndex);

      _status = PanelStatus.idle;
      _finish();
    } on OperationCanceled {
      if (requestId == _requestId) {
        _status = PanelStatus.idle;
        _finish();
      }
    } on FsError catch (error) {
      if (requestId != _requestId) {
        return;
      }
      _status = PanelStatus.error;
      _error = error;
      _finish(statusText: error.message);
    }
  }

  void _finish({String? statusText}) {
    _busy = false;
    _statusText = statusText;
    _operation = null;
    notifyListeners();
  }

  void _applySort() {
    final sorted = _nodes.toList()..sort(comparatorFor(_sort));
    _nodes = List.unmodifiable(sorted);
  }

  /// После перечитывания узлы — новые экземпляры, поэтому пометка переносится
  /// по именам; исчезнувшие объекты отбрасываются.
  void _restoreSelection(Set<String>? markedNames) {
    selection.clear();
    if (markedNames == null || markedNames.isEmpty) {
      return;
    }
    selection.addAll(_nodes.where((node) => markedNames.contains(node.name)));
  }

  /// Курсор ищется по имени; если объект исчез — встаёт на ближайший индекс
  /// от прежней позиции.
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
    notifyListeners();
  }

  /// Приводит узел к каталогу: ссылку на каталог разворачивает.
  Future<DirectoryNode?> _asDirectory(FsNode? node) async {
    if (node is DirectoryNode) {
      return node;
    }
    if (node is LinkNode) {
      final target = await _resolve(node);
      return target is DirectoryNode ? target : null;
    }
    if (node == null) {
      return null;
    }

    // Файл, который открывается как каталог, — архив, набранный путём. Так
    // замыкается круг: панель в корне архива показывает `/home/a.zip`, и эта
    // же строка обязана вернуть туда обратно. То же самое делает Enter на нём.
    final scheme = _registry.schemeFor(node);
    if (scheme == null) {
      return null;
    }
    return (await _registry.mount(scheme, node)).rootDirectory;
  }

  Future<FsNode?> _resolve(LinkNode link) async {
    if (link.target != null) {
      return link.target;
    }
    try {
      return await link.provider.resolveLink(link).result;
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
  final Map<DirectoryNode, _SizeScan> _scans = {};

  /// Строка состояния обновляется не на каждый посчитанный файл.
  late final Throttle _sizeRedraw = Throttle(notifyListeners);

  /// Суммарный размер помеченных объектов.
  ///
  /// Размер файлов известен сразу, содержимое каталогов считается фоном,
  /// поэтому значение растёт по ходу обхода. Закончен ли подсчёт, говорит
  /// [selectionSizeIsFinal].
  ///
  /// Отдельного счётчика здесь нет: посчитанное лежит в самих узлах, поэтому
  /// сумма и колонка «Size» в таблице показывают одно и то же число и разойтись
  /// не могут.
  @override
  int get selectionSize => selection.totalSize;

  @override
  bool get selectionSizeIsFinal => _scans.isEmpty && _scanQueue.isEmpty;

  /// Пометка изменилась: новые каталоги встают в очередь, снятые — уходят.
  ///
  /// Идущий обход при этом не прерывается: помечать файлы продолжают по ходу
  /// подсчёта, и начинать всё заново на каждое нажатие было бы напрасной
  /// работой — до конца дело не дошло бы никогда.
  void _onSelectionChanged() {
    final selected = selection.nodes.whereType<DirectoryNode>().toSet();

    // Снятое с пометки ждать в очереди перестаёт, но уже посчитанный размер
    // в узле остаётся: он всё ещё верен, и в колонке его видно.
    _scanQueue.removeWhere((directory) => !selected.contains(directory));

    for (final directory in _scans.keys.toList()) {
      if (!selected.contains(directory)) {
        _cancelScan(directory);
      }
    }

    for (final directory in selected) {
      // Посчитанный каталог второй раз не обходим: значение в узле авторитетно
      // до перечитывания каталога.
      if (directory.size != FsNode.unknownSize || _scans.containsKey(directory) || _scanQueue.contains(directory)) {
        continue;
      }
      _scanQueue.add(directory);
    }

    _fillPool();
    notifyListeners();
  }

  /// Настоящий предел пула: меньшее из настройки приложения и того, что
  /// провайдер о себе объявил.
  ///
  /// Настройка говорит, сколько обходов сразу нужно **пользователю**;
  /// провайдер — сколько он **выдерживает**. Локальному диску десяток только
  /// на пользу, а FTP-серверу столько же обходов — способ получить отказ.
  int get _scanConcurrency => math.min(sizeScanConcurrency, provider.capabilities.maxConcurrency);

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
    final operation = directory.provider.calculateSize([directory]);
    final scan = _SizeScan(operation);
    _scans[directory] = scan;

    scan.progress = operation.progress.listen((event) {
      // Событие может доехать после того, как этот обход отменили или он
      // закончился: между `report` и слушателем есть задержка в микрозадачу.
      // Без проверки итог сменился бы частичной суммой.
      if (!identical(_scans[directory], scan)) {
        return;
      }
      directory.size = event.processed;
      _sizeRedraw();
    });

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
    if (!identical(_scans[directory], scan)) {
      // Обход отменили, а результат опоздал — он уже ни о чём.
      return;
    }

    directory.size = total < 0 ? 0 : total;
    _scans.remove(directory);
    scan.release();
    _fillPool();
    _sizeRedraw.flush();
  }

  /// Прекращает обход одного каталога, не трогая ни остальные, ни очередь.
  void _cancelScan(DirectoryNode directory) {
    final scan = _scans.remove(directory);
    if (scan == null) {
      return;
    }
    scan.cancel();
    // Частичная сумма, застывшая в колонке как итог, — ложь.
    directory.size = FsNode.unknownSize;
  }

  /// Забывает и идущие обходы, и очередь.
  ///
  /// Очередь чистится без сброса размеров: в неё попадают только каталоги
  /// с непосчитанным размером, сбрасывать там нечего.
  void _stopSizeScan() {
    for (final directory in _scans.keys.toList()) {
      _cancelScan(directory);
    }
    _scanQueue.clear();
    _sizeRedraw.cancel();
  }

  @override
  void dispose() {
    _operation?.cancel();
    _stopSizeScan();
    // Панель закрылась вместе с приложением, а архив остался открытым.
    _releaseProvider(_directory?.provider, keeping: _registry.root);
    // Своё подключение закрывается вместе с панелью: держать его больше некому.
    unawaited(_releaseOwnRoot());
    selection.removeListener(_onSelectionChanged);
    selection.dispose();
    super.dispose();
  }
}

/// Один идущий обход каталога: сама операция и подписка на её сообщения.
class _SizeScan {
  _SizeScan(this.operation);

  final AsyncOperation<int> operation;
  StreamSubscription<OperationProgress>? progress;

  void release() {
    unawaited(progress?.cancel());
    progress = null;
  }

  void cancel() {
    operation.cancel();
    release();
  }
}
