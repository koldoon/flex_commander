import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

import 'node_info.dart';
import 'panel_steps.dart';
import 'session.dart';

/// Сессия **только для чтения** поверх готовых строк — без ядра и без вкладки.
///
/// Так окно рисует список стандартным видом панели, не заводя для него
/// источника: удаление мимо корзины показывает, что уйдёт навсегда, тем же
/// сжатым деревом, что и находки поиска (`docs/spec/trash-unavailable.md`,
/// §4а). Вид спрашивает строки, курсор и прокрутку — они и есть всё её
/// состояние. Остальное ничего не меняет: ходить, помечать и читать здесь
/// нечего, строки — снимок.
class SnapshotSession extends ChangeNotifier implements Session {
  SnapshotSession({
    required this.id,
    required this.entries,
    this.rows = RowsKind.compactTree,
    this.view = 'compactTree',
    this.source = const SourceInfo(scheme: ''),
  });

  @override
  final PanelId id;

  @override
  final List<FileEntry> entries;

  @override
  final RowsKind rows;

  @override
  final String view;

  @override
  final SourceInfo source;

  // --- курсор и прокрутка: своё у снимка ---

  @override
  int get cursorIndex => _cursorIndex;
  int _cursorIndex = 0;

  @override
  FileEntry? get currentEntry => _cursorIndex >= 0 && _cursorIndex < entries.length ? entries[_cursorIndex] : null;

  @override
  int pageSize = 1;

  @override
  PanelSteps cursorSteps = const PanelSteps.list();

  @override
  void setCursorIndex(int index) {
    final next = entries.isEmpty ? 0 : index.clamp(0, entries.length - 1);
    if (next == _cursorIndex) {
      return;
    }
    _cursorIndex = next;
    notifyListeners();
  }

  @override
  void moveCursor(int delta) => setCursorIndex(_cursorIndex + delta);

  @override
  void moveCursorPage(int direction) => moveCursor(direction * (pageSize - 1).clamp(1, pageSize));

  @override
  void setCursorToFirst() => setCursorIndex(0);

  @override
  void setCursorToLast() => setCursorIndex(entries.length - 1);

  @override
  void setCursorToName(String name) {
    final index = entries.indexWhere((entry) => entry.name == name);
    if (index >= 0) {
      setCursorIndex(index);
    }
  }

  @override
  void setCursorToPath(String path) {
    final index = entries.indexWhere((entry) => entry.path == path);
    if (index >= 0) {
      setCursorIndex(index);
    }
  }

  @override
  double get scrollOffset => _scrollOffset;
  double _scrollOffset = 0;

  @override
  void setScrollOffset(double offset) => _scrollOffset = offset;

  @override
  double? rememberedScroll(String path) => null;

  // --- где стоит: в корне снимка, и уйти отсюда некуда ---

  @override
  String get currentPath => entries.isEmpty ? '' : entries.first.path;

  @override
  String get directoryName => entries.isEmpty ? '' : entries.first.name;

  @override
  String get shellDirectory => '';

  @override
  bool get canGoUp => false;

  @override
  PanelPhase get phase => PanelPhase.idle;

  @override
  FsError? get error => null;

  @override
  bool get busy => false;

  /// Не панель: клавиши разбирает окно, где снимок стоит.
  @override
  bool get active => false;

  @override
  bool get takesKeyboard => false;

  @override
  String? get statusText => null;

  @override
  void setStatusText(String? text) {}

  @override
  String? get headerText => null;

  @override
  void setHeaderText(String? text) {}

  @override
  void follow(String directory, {String name = ''}) {}

  @override
  Future<bool> openPath(String path, {bool allowConnect = true}) async => false;

  @override
  Future<List<FileEntry>> namesIn(String path) async => const [];

  @override
  Future<FileEntry?> enter(FileEntry entry) async => null;

  @override
  Future<FileEntry?> enterCurrent() async => null;

  @override
  Future<void> goUp() async {}

  @override
  bool get canGoBack => false;

  @override
  bool get canGoForward => false;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> goForward() async {}

  @override
  Future<void> goToStep(int index) async {}

  @override
  Future<({List<PathStep> steps, int index})> history() async => (steps: const <PathStep>[], index: 0);

  @override
  Future<void> reload() async {}

  @override
  void cancel() {}

  @override
  void close() {}

  // --- объекты: у снимка их нет, только строки ---

  @override
  Content contentOf(FileEntry entry) => throw UnsupportedError('Снимок не читает содержимого');

  @override
  NodeSource sourceOf(FileEntry entry) => throw UnsupportedError('Снимок не читает содержимого');

  @override
  Future<NodeAttributes> readAttributes(FileEntry entry) =>
      Future.error(UnsupportedError('Снимок не читает атрибутов'));

  @override
  Future<bool> canWriteTo(FileEntry entry) async => false;

  @override
  Future<bool> followLink(String path) async => false;

  @override
  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String? status}) =>
      Future.error(UnsupportedError('Снимок работ не заводит'));

  // --- пометка и цели: помечать в снимке нечего ---

  @override
  Set<String> get markedPaths => const {};

  @override
  bool isMarked(FileEntry entry) => false;

  @override
  void setMarks(Set<String> paths, {MarkChange by = MarkChange.person}) {}

  @override
  void mark(FileEntry entry) {}

  @override
  void unmark(FileEntry entry) {}

  @override
  void markAll() {}

  @override
  void clearMarks({required MarkChange by}) {}

  @override
  void toggleCurrentMark({bool step = true}) {}

  @override
  List<FileEntry> get targets => const [];

  @override
  Set<String> get targetPaths => const {};

  @override
  bool get hasTargets => false;

  @override
  bool get targetsWritable => false;

  @override
  bool get targetsRenamable => false;

  @override
  Future<List<FileEntry>> allTargets() async => const [];

  @override
  Future<({List<FileEntry> rows, int count})> untrashableTargets() async => (rows: const <FileEntry>[], count: 0);

  @override
  EntryRef? get currentRef => null;

  @override
  int? sizeOf(String path) => null;

  @override
  int get markedSize => 0;

  @override
  bool get markedSizeIsFinal => true;

  @override
  void measureDirectories() {}

  // --- вид: снимок показывают как есть ---

  @override
  bool get sorted => false;

  @override
  ColumnLayout get columns => ColumnLayout.empty;

  @override
  void setColumnLayout(ColumnLayout layout) {}

  @override
  Future<void> showRows(RowsKind kind) async {}

  @override
  void setExpanded(String path, {required bool expanded}) {}

  @override
  Future<PanelExpansion> expandDeep(String path, {required bool expanded}) async =>
      const PanelExpansion(opened: 0, stopped: false);

  @override
  SortSpec get sort => const SortSpec();

  @override
  void sortBy(String column) {}

  @override
  bool get showHidden => true;

  @override
  Future<void> setShowHidden(bool value) async {}

  @override
  Future<void> setView(String view) async {}
}
