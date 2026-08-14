import 'package:flutter/foundation.dart';

import '../model/async/async_operation.dart';
import '../model/panel/column_spec.dart';
import '../model/panel/sort_spec.dart';
import '../model/settings/app_settings.dart';
import '../model/tree/fs_node.dart';
import '../model/tree/node_path.dart';
import '../model/tree/tree_provider.dart';
import 'panel_selection.dart';

enum PanelStatus { idle, loading, error }

/// Состояние одной панели: открытый каталог, отсортированный список, курсор,
/// пометка и настройки вида.
///
/// Ничего не знает ни о второй панели, ни о виджетах: панели симметричны, а
/// связывает их [AppController].
class PanelController extends ChangeNotifier {
  PanelController({required this.provider, required PanelSettings settings})
    : _columns = settings.columns,
      _sort = settings.sort,
      _showHidden = settings.showHidden,
      _lastPath = settings.path;

  final TreeProvider provider;

  /// Сколько строк помещается в видимой части списка. Значение выставляет
  /// таблица; от него считается шаг PgUp/PgDn.
  int pageSize = 20;

  final PanelSelection selection = PanelSelection();

  DirectoryNode? _directory;
  List<FsNode> _nodes = const [];
  PanelStatus _status = PanelStatus.idle;
  FsError? _error;
  int _cursorIndex = 0;
  bool _busy = false;
  bool _active = false;
  String? _statusText;
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
  /// долгой работе; между запусками карта не сохраняется.
  static const int cursorMemoryLimit = 100;

  // --- каталог ---

  DirectoryNode? get directory => _directory;

  /// Отсортированное содержимое каталога — то, что рисует таблица.
  List<FsNode> get nodes => _nodes;

  PanelStatus get status => _status;

  FsError? get error => _error;

  /// Идёт длительная операция: клавиатура игнорируется, кроме отмены.
  bool get busy => _busy;

  /// Панель активна: в ней курсор и ввод с клавиатуры.
  /// Значение выставляет [AppController], чтобы активной всегда была ровно одна.
  bool get active => _active;

  /// Текст, выставленный командой ("Loading…", сообщение об ошибке).
  /// null — строка состояния показывает объект под курсором.
  String? get statusText => _statusText;

  /// Открыть каталог. Отменяет незавершённое чтение этой же панели.
  Future<void> open(DirectoryNode dir) {
    return _load(dir, cursorName: _cursorMemory[dir.pathString]);
  }

  /// Открыть каталог по строке пути. Возвращает false, если путь недоступен
  /// или это не каталог — тогда вызывающий код решает, куда открыть панель.
  Future<bool> openPath(String path) async {
    final target = NodePath.parse(path).last.path;

    // Разбор пути тоже обращается к провайдеру и может быть небыстрым,
    // поэтому панель занята уже на этом шаге, а не только на чтении каталога.
    final requestId = ++_requestId;
    _busy = true;
    _status = PanelStatus.loading;
    _statusText = 'Loading…';
    notifyListeners();

    final resolving = provider.resolvePath(target);
    _operation = resolving;

    DirectoryNode? dir;
    try {
      dir = await _asDirectory(await resolving.result);
    } on FsError {
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
      _status = PanelStatus.idle;
      _finish();
      return false;
    }

    await _load(dir, cursorName: _cursorMemory[dir.pathString]);
    return _status != PanelStatus.error;
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
      return target ?? node;
    }
    return node;
  }

  /// На уровень вверх. Курсор встаёт на покинутый каталог.
  Future<void> goUp() async {
    final dir = _directory;
    final parent = dir?.parentDirectory;
    if (dir == null || parent == null) {
      return;
    }
    await _load(parent, cursorName: dir.name);
  }

  /// Перечитать текущий каталог, сохранив курсор и пометку.
  Future<void> reload() async {
    final dir = _directory;
    if (dir == null) {
      return;
    }
    await _load(dir, cursorName: currentNode?.name, cursorFallbackIndex: _cursorIndex, markedNames: selection.names);
  }

  /// Прервать текущее чтение.
  void cancel() => _operation?.cancel();

  // --- курсор ---

  int get cursorIndex => _cursorIndex;

  FsNode? get currentNode => _cursorIndex >= 0 && _cursorIndex < _nodes.length ? _nodes[_cursorIndex] : null;

  void moveCursor(int delta) => setCursorIndex(_cursorIndex + delta);

  /// Сдвинуть курсор на страницу: `direction` равен -1 или 1.
  void moveCursorPage(int direction) => moveCursor(direction * (pageSize - 1).clamp(1, pageSize));

  void setCursorIndex(int index) {
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
  void toggleCurrentMark() {
    final node = currentNode;
    if (node == null || node is ParentDirNode) {
      return;
    }
    selection.toggle(node);
    moveCursor(1);
  }

  void markAll() => selection.addAll(_nodes);

  // --- вид ---

  ColumnLayout get columns => _columns;

  void setColumnLayout(ColumnLayout layout) {
    _columns = layout;
    notifyListeners();
  }

  SortSpec get sort => _sort;

  /// Сортировка по колонке: та же колонка меняет направление.
  /// Курсор остаётся на том же объекте, а не на том же индексе.
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

  bool get showHidden => _showHidden;

  Future<void> setShowHidden(bool value) async {
    if (_showHidden == value) {
      return;
    }
    _showHidden = value;
    notifyListeners();
    await reload();
  }

  void setStatusText(String? text) {
    if (_statusText == text) {
      return;
    }
    _statusText = text;
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
  PanelSettings get settings =>
      PanelSettings(path: _directory?.pathString ?? _lastPath, columns: _columns, sort: _sort, showHidden: _showHidden);

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

    final operation = provider.getDirectoryListing(dir, includeHidden: _showHidden);
    _operation = operation;

    try {
      final nodes = await operation.result;
      if (requestId != _requestId) {
        // Пользователь уже запросил другой каталог — этот результат не нужен.
        return;
      }

      _directory = dir;
      _lastPath = dir.pathString;
      _nodes = nodes;
      _applySort();
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
    return null;
  }

  Future<FsNode?> _resolve(LinkNode link) async {
    if (link.target != null) {
      return link.target;
    }
    try {
      return await provider.resolveLink(link).result;
    } on FsError {
      return null;
    }
  }

  @override
  void dispose() {
    _operation?.cancel();
    selection.dispose();
    super.dispose();
  }
}
