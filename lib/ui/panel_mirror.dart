import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';

import '../link/link.dart';

/// Панель со стороны экрана: зеркало того, что держит ядро.
///
/// Своего состояния у зеркала нет — есть последнее, о чём рассказало ядро.
/// Просьбы уходят за границу, ответы приходят событиями, и между ними
/// проходит оборот линка. Поэтому две вещи зеркало делает **сразу**, не
/// дожидаясь ответа: двигает курсор и пишет строку состояния. Ядро остаётся
/// хозяином и поправит расхождение — но при удержании стрелки курсор не имеет
/// права отставать на кадр (`docs/spec/client-server.md`, §5.5).
///
/// Всё остальное ждёт ответа: открытие каталога, сортировка, работы. Там
/// задержка неразличима на фоне самого дела.
class PanelMirror extends ChangeNotifier {
  PanelMirror({required this.id, required Link link, required PanelState state, required PanelListing listing})
    : _link = link,
      _state = state,
      _listing = listing {
    _events = link.events.listen(_apply);
  }

  final PanelId id;
  final Link _link;
  late final StreamSubscription<CoreEvent> _events;

  PanelState _state;
  PanelListing _listing;

  /// Номер последней **своей** заявки на курсор.
  ///
  /// Подтверждение с меньшим номером — опоздавшее: пока оно шло, человек успел
  /// нажать стрелку ещё раз, и слушать его значит дёргать курсор назад.
  int _cursorSeq = 0;

  PanelState get state => _state;

  List<FileEntry> get entries => _listing.entries;

  SourceInfo get source => _state.source;

  String get path => _state.path;

  String get shellDirectory => _state.shellDirectory;

  Future<List<FileEntry>> namesIn(String path) async {
    final reply = await _link.call(ListNames(id, path));
    return reply is CoreEntries ? reply.entries : const [];
  }

  PanelPhase get phase => _state.phase;

  FsError? get error => _state.error;

  bool get busy => _state.busy;

  String? get statusText => _state.statusText;

  String? get headerText => _state.headerText;

  SortSpec get sort => _state.sort;

  ColumnLayout get columns => _state.source.columns ?? _state.columns;

  bool get showHidden => _state.showHidden;

  Set<String> get marked => _state.marked;

  int get markedSize => _state.markedSize;

  bool get markedSizeIsFinal => _state.markedSizeIsFinal;

  // --- курсор ---

  /// Сколько строк помещается в видимой части списка; от этого считается шаг
  /// страницей. Значение выставляет таблица и на ту сторону оно не едет: шаг
  /// страницей — про показ, а список у этой стороны на руках.
  int pageSize = 20;

  int get cursorIndex => _state.cursorIndex;

  FileEntry? get currentEntry =>
      _state.cursorIndex >= 0 && _state.cursorIndex < entries.length ? entries[_state.cursorIndex] : null;

  void moveCursor(int delta) => setCursorIndex(_state.cursorIndex + delta);

  void moveCursorPage(int direction) => moveCursor(direction * (pageSize - 1).clamp(1, pageSize));

  void setCursorToFirst() => setCursorIndex(0);

  void setCursorToLast() => setCursorIndex(entries.length - 1);

  void setCursorToName(String name) {
    final index = entries.indexWhere((entry) => entry.name == name);
    if (index >= 0) {
      setCursorIndex(index);
    }
  }

  void setCursorIndex(int index) {
    final clamped = entries.isEmpty ? 0 : index.clamp(0, entries.length - 1);
    if (clamped == _state.cursorIndex) {
      return;
    }
    _cursorSeq++;
    // Сразу к себе — и следом просьбой: кадр рисуется этой стороной, и ждать
    // ради него оборота границы нечего.
    _state = _state.copyWith(cursorIndex: clamped, cursorSeq: _cursorSeq);
    _link.tell(MoveCursor(id, clamped, _cursorSeq));
    notifyListeners();
  }

  // --- пометка ---

  bool isMarked(FileEntry entry) => _state.marked.contains(entry.name);

  void setMarks(Set<String> names) {
    _state = _state.copyWith(marked: names);
    _link.tell(SetMarks(id, names));
    notifyListeners();
  }

  void mark(FileEntry entry) => setMarks({..._state.marked, entry.name});

  void unmark(FileEntry entry) => setMarks({..._state.marked}..remove(entry.name));

  void markAll() => setMarks({
    for (final entry in entries)
      if (!entry.isParent) entry.name,
  });

  void clearMarks() => setMarks(const {});

  /// Пометить объект под курсором и сдвинуть курсор вниз.
  ///
  /// Одной просьбой: пометка и курсор здесь — одно действие, и разложить его
  /// на две значило бы разрешить им разъехаться.
  void toggleCurrentMark() => _link.tell(ToggleMark(id));

  /// Помеченное, а если не помечено ничего — объект под курсором.
  ///
  /// То самое правило, по которому работают все файловые операции.
  List<FileEntry> get targets {
    if (_state.marked.isEmpty) {
      final current = currentEntry;
      return current == null || current.isParent ? const [] : [current];
    }
    return [
      for (final entry in entries)
        if (_state.marked.contains(entry.name)) entry,
    ];
  }

  // --- подписи ---

  void setStatusText(String? text) {
    if (_state.statusText == text) {
      return;
    }
    _state = _state.copyWith(statusText: text, clearStatus: text == null);
    _link.tell(SetStatusText(id, text));
    notifyListeners();
  }

  void setHeaderText(String? text) {
    if (_state.headerText == text) {
      return;
    }
    _state = _state.copyWith(headerText: text, clearHeader: text == null);
    _link.tell(SetHeaderText(id, text));
    notifyListeners();
  }

  // --- переходы ---

  Future<bool> openPath(String path, {bool allowConnect = true}) async {
    final reply = await _link.call(OpenPath(id, path, allowConnect: allowConnect));
    return reply is CoreOpened && reply.opened;
  }

  /// Войти в строку списка. Возвращает то, во что войти нельзя; null — вошли.
  Future<FileEntry?> enter(FileEntry entry) async {
    final index = entries.indexOf(entry);
    if (index < 0) {
      return null;
    }
    final reply = await _link.call(OpenEntry(id, EntryRef.inPanel(id, index, _listing.generation)));
    return reply is CoreEntered ? reply.entry : null;
  }

  Future<FileEntry?> enterCurrent() async {
    final current = currentEntry;
    return current == null ? null : enter(current);
  }

  Future<void> goUp() => _link.call(GoUp(id));

  Future<void> reload() => _link.call(Reload(id));

  void cancel() => _link.tell(CancelWork(id));

  void measureDirectories() => _link.tell(MeasureDirectories(id));

  // --- вид ---

  Future<void> sortBy(FsColumn column) {
    if (!column.sortable) {
      return Future.value();
    }
    return _link.call(Arrange(id, sort: _state.sort.toggled(column)));
  }

  Future<void> setColumnLayout(ColumnLayout layout) => _link.call(Arrange(id, columns: layout));

  Future<void> setShowHidden(bool value) => _link.call(Arrange(id, showHidden: value));

  // --- зеркалирование ---

  void _apply(CoreEvent event) {
    switch (event) {
      case PanelChanged(:final panel, :final state) when panel == id:
        // Курсор берётся из ответа только если он про нашу последнюю заявку:
        // опоздавший вернул бы его назад.
        final stale = state.cursorSeq < _cursorSeq;
        _state = stale ? state.copyWith(cursorIndex: _state.cursorIndex, cursorSeq: _cursorSeq) : state;
        notifyListeners();

      case PanelListed(:final panel, :final listing) when panel == id:
        _listing = listing;
        notifyListeners();

      case PanelSized(:final panel, :final generation, :final sizes) when panel == id:
        if (generation != _listing.generation) {
          // Числа не про этот список: пока они шли, каталог перечитали.
          return;
        }
        final entries = _listing.entries.toList();
        for (final entry in sizes.entries) {
          if (entry.key >= 0 && entry.key < entries.length) {
            entries[entry.key] = entries[entry.key].withSize(entry.value);
          }
        }
        _listing = PanelListing(generation: generation, entries: entries);
        notifyListeners();

      case CoreEvent():
        // Про другую панель — не наше дело.
        break;
    }
  }

  @override
  void dispose() {
    unawaited(_events.cancel());
    super.dispose();
  }
}
