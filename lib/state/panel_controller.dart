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
/// Предел обхода, когда его не назвали, — тот же, что в настройках.
int _defaultConcurrency() => AppSettings.defaultSizeScanConcurrency;

class PanelControllerFactory {
  PanelControllerFactory({
    required this.registry,
    required this.editor,
    this.sizeScanConcurrency = _defaultConcurrency,
    this.naming = const ReferenceFileNaming(),
  });

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

  PanelController create(PanelSettings settings) => PanelController(
    registry: registry,
    editor: editor,
    settings: settings,
    sizeScanConcurrency: sizeScanConcurrency,
    naming: naming,
  );
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
    this.sizeScanConcurrency = _defaultConcurrency,
    this.naming = const ReferenceFileNaming(),
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

  /// Правило показа имени: по нему же идёт сортировка по расширению.
  final FileNaming naming;

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

  /// Ещё одна аренда на то, в чём панель стоит сейчас; null — общий корень.
  ///
  /// Панель при этом остаётся арендатором сама: у длительной работы своя
  /// аренда, и уход панели её не касается.
  @override
  ProviderLease? leaseProvider() => _registry.leaseOf(provider);

  /// Разбирает путь от корня этой панели и отдаёт узел вместе с арендой.
  ///
  /// Аренду обязан отпустить тот, кто просил: путь может пройти через архив,
  /// который ради него и смонтируют. Уже открытый архив вторым экземпляром не
  /// становится — реестр отдаёт того же и просто считает арендаторов.
  @override
  Operation<String, ResolvedNode> resolvePath() => TaskOperation<String, ResolvedNode>(
    (op, path) => op.delegate(_registry.resolveDisplayPath(), ResolvePathParams(path, from: _root)),
  );

  @override
  Future<bool> openPath(String path, {bool allowConnect = true}) async {
    // Прежняя работа панели уступает место: без этого она осталась бы читать
    // впустую — номер запроса не даст применить её итог, но сама она про это
    // не знает и продолжит тянуть байты с сервера. Так же начинает и `_load`.
    _operation?.cancel();

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
        _status = PanelStatus.idle;
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
      _status = PanelStatus.idle;
      _finish();
      return false;
    }

    await _load(dir, lease: resolved.lease, cursorName: _cursorMemory[dir.pathString]);
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
    _status = PanelStatus.loading;
    _statusText = 'Opening ${node.name}…';
    notifyListeners();

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
      _status = PanelStatus.idle;
      _statusText = null;
    } on FsError catch (error) {
      // Битый архив — это отказ открыть, а не пустой каталог: панель остаётся
      // на месте и говорит почему.
      _error = error;
      _status = PanelStatus.error;
      _statusText = error.message;
    } finally {
      release();
      if (identical(_operation, mounting)) {
        _operation = null;
      }
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

  /// Прервать текущую работу панели.
  ///
  /// Внутрь отмена доходит сама: разбор пути — это операция, внутри которой
  /// идут подключение, монтирование и чтение, и каждая вложенная прерывается
  /// вместе с ней (`AsyncOperation.delegate`).
  @override
  void cancel() => _operation?.cancel();

  @override
  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String status = 'Loading…'}) async {
    final operation = TaskOperation<void, R>((op, _) => body(op));

    // Прежняя работа уступает место, а не отказывает новой: правило то же, что
    // у чтения каталога, — последнее сказанное человеком главнее.
    _operation?.cancel();

    final requestId = ++_requestId;
    _busy = true;
    _statusText = status;
    _operation = operation;
    // `PanelStatus` нарочно не трогается: панель не перечитывается, и список
    // файлов обязан остаться на виду — читается один файл, а не каталог.
    final release = _followProgress(operation, requestId);
    notifyListeners();

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
      notifyListeners();
    }
  }

  /// Фокус панелям не нужен: какая область активна, знает приложение, а
  /// нажатия разбирает ранний обработчик клавиатуры.
  @override
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
  @override
  void close() {
    _operation?.cancel();
    unawaited(_releaseRoot());
    final lease = _lease;
    _lease = null;
    unawaited(lease?.release() ?? Future<void>.value());
  }

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

  // --- быстрый поиск ---

  @override
  String? get quickSearch => _quickSearch;
  String? _quickSearch;

  @override
  void setQuickSearch(String? pattern) {
    if (_quickSearch == pattern) {
      return;
    }
    _quickSearch = pattern;
    notifyListeners();
  }

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
    ProviderLease? lease,
    String? cursorName,
    int? cursorFallbackIndex,
    Set<String>? markedNames,
  }) async {
    _rememberCursor();
    _operation?.cancel();
    // Образец быстрого поиска относится к **этому** списку: в новом каталоге
    // он ничего не значит и вводил бы в заблуждение.
    _quickSearch = null;

    final requestId = ++_requestId;
    _busy = true;
    _status = PanelStatus.loading;
    _error = null;
    _statusText = 'Loading…';
    notifyListeners();

    final operation = dir.provider.getDirectoryListing();
    _operation = operation;
    operation.start(ListingParams(dir, includeHidden: _showHidden));

    var adopted = false;
    try {
      final nodes = await operation.result;
      if (requestId != _requestId) {
        // Пользователь уже запросил другой каталог — этот результат не нужен.
        return;
      }

      _directory = dir;
      _lastPath = dir.pathString;
      // Каталог сменился — сменилась и аренда. Делается это здесь, а не там,
      // откуда уходят: способов уйти много (открыть, подняться, набрать путь),
      // а место, где каталог сменился, одно.
      _adoptLease(lease, dir);
      adopted = true;
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
    final redraw = Throttle(notifyListeners);
    final status = operation.status;
    void onChanged() {
      final message = status.message;
      if (requestId != _requestId || message.isEmpty || _statusText == message) {
        return;
      }
      _statusText = message;
      redraw();
    }

    status.addListener(onChanged);

    return () {
      redraw.cancel();
      status.removeListener(onChanged);
    };
  }

  void _finish({String? statusText}) {
    _busy = false;
    _statusText = statusText;
    _operation = null;
    notifyListeners();
  }

  void _applySort() {
    // Тем же правилом, что рисует колонку: иначе имя стояло бы под одним
    // расширением, а сортировалось по другому.
    final sorted = _nodes.toList()..sort(comparatorFor(_sort, naming: naming));
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

  /// Идёт общий подсчёт: считаем до конца, что бы ни делали с пометкой.
  ///
  /// Признак, а не второй список: очередь остаётся одна, меняется лишь
  /// основание, по которому в ней держат каталог.
  bool _measuringAll = false;

  /// Посчитать размеры всех каталогов текущего каталога.
  @override
  void measureDirectories() {
    _measuringAll = true;
    for (final node in _nodes) {
      // `..` пропускается: подсчёт родителя — это подсчёт всего дерева выше, и
      // по нажатию в панели такого не ждут.
      if (node is! DirectoryNode || node is ParentDirNode) {
        continue;
      }
      // Посчитанный каталог второй раз не обходим: значение в узле авторитетно
      // до перечитывания каталога.
      if (node.size != FsNode.unknownSize || _scans.containsKey(node) || _scanQueue.contains(node)) {
        continue;
      }
      _scanQueue.add(node);
    }

    _fillPool();
    _statusText = _scansRunning ? measuringStatus : _statusText;
    notifyListeners();
  }

  /// Что показывает строка состояния, пока идёт общий подсчёт.
  ///
  /// На медленном источнике прочерки сменяются числами не сразу, и без этой
  /// строки нажатие выглядит как «ничего не произошло».
  static const String measuringStatus = 'Measuring directories…';

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

      for (final directory in _scans.keys.toList()) {
        if (!selected.contains(directory)) {
          _cancelScan(directory);
        }
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
    final operation = directory.provider.calculateSize();
    final scan = _SizeScan(operation);
    _scans[directory] = scan;

    final status = operation.status;
    void onChanged() {
      // Обход могли отменить или заменить другим, пока этот ещё рассказывает
      // о себе. Без проверки итог сменился бы частичной суммой.
      if (!identical(_scans[directory], scan) || status is! MultipleTransferOperationStatus) {
        return;
      }
      directory.size = status.itemsTransferred;
      _sizeRedraw();
    }

    status.addListener(onChanged);
    scan.stopWatching = () => status.removeListener(onChanged);
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
    if (!identical(_scans[directory], scan)) {
      // Обход отменили, а результат опоздал — он уже ни о чём.
      return;
    }

    directory.size = total < 0 ? 0 : total;
    _scans.remove(directory);
    scan.release();
    _fillPool();
    _sizeRedraw.flush();

    if (!_scansRunning) {
      _finishMeasuring();
    }
  }

  /// Очередь опустела: подвести итог общего подсчёта.
  ///
  /// Сортировка по ходу обхода не пересчитывается вовсе — иначе при сортировке
  /// по размеру строки прыгали бы под курсором десятки раз в секунду. Но при
  /// подсчёте **всех** каталогов колонка меняется целиком, и оставить прежний
  /// порядок значило бы показать список, отсортированный по вчерашним числам.
  /// Поэтому один пересчёт — здесь.
  void _finishMeasuring() {
    if (!_measuringAll) {
      return;
    }
    _measuringAll = false;
    if (_statusText == measuringStatus) {
      _statusText = null;
    }

    if (_sort.column == FsColumn.size) {
      // Курсор держится за **объект**, а не за место: строка уедет, и следить
      // надо за тем, на чём стоял курсор.
      final current = currentNode?.name;
      _applySort();
      if (current != null) {
        setCursorToName(current);
      }
    }

    notifyListeners();
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
    // Уход из каталога подсчёт прекращает: считать то, на что уже не смотрят,
    // незачем.
    _measuringAll = false;
    if (_statusText == measuringStatus) {
      _statusText = null;
    }
  }

  @override
  void dispose() {
    _operation?.cancel();
    _stopSizeScan();
    // Панель ушла — она больше не арендатор ни архива, ни своего сервера.
    // Закроются они, только если держать их больше некому: работа, ушедшая в
    // фон, продолжает читать то, из чего панель уже вышла.
    unawaited(_lease?.release());
    _lease = null;
    unawaited(_releaseRoot());
    selection.removeListener(_onSelectionChanged);
    selection.dispose();
    super.dispose();
  }
}

/// Один идущий обход каталога: сама операция и подписка на её сообщения.
class _SizeScan {
  _SizeScan(this.operation);

  final Operation<List<FsNode>, int> operation;

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
