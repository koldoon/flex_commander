import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import '../link/link.dart';
import 'remote_content.dart';

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
///
/// Третья предсказанная вещь — **занятость своей работой**. Чтение файла на
/// просмотр или правку ведёт экран: там буфер, там окно, там `Esc`. Панель на
/// это время занята, и знать об этом надо здесь и сейчас — а ядру о том же
/// говорится строкой состояния, чтобы обе стороны сходились.
class PanelMirror extends ChangeNotifier implements Panel {
  PanelMirror({required this.id, required Link link, required PanelState state, required PanelListing listing})
    : _link = link,
      _state = state,
      _listing = listing {
    _events = link.events.listen(_apply);
  }

  @override
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

  @override
  List<FileEntry> get entries => _listing.entries;

  @override
  SourceInfo get source => _state.source;

  @override
  String get path => _state.path;

  @override
  String get shellDirectory => _state.shellDirectory;

  @override
  Future<bool> showFound(String runId, {String title = ''}) async {
    final reply = await _link.call(ShowFound(id, runId, title: title));
    return reply is CoreOpened && reply.opened;
  }

  @override
  Future<List<FileEntry>> namesIn(String path) async {
    final reply = await _link.call(ListNames(id, path));
    return reply is CoreEntries ? reply.entries : const [];
  }

  @override
  PanelPhase get phase => _state.phase;

  @override
  FsError? get error => _state.error;

  /// Занята делом: своим или ядровым.
  ///
  /// Своё — чтение файла на просмотр или правку: его ведёт экран, и знать о
  /// занятости надо здесь, не дожидаясь оборота границы.
  @override
  bool get busy => _state.busy || _work != null;

  @override
  String? get statusText => _workStatus ?? _state.statusText;

  @override
  String? get headerText => _state.headerText;

  @override
  SortSpec get sort => _state.sort;

  @override
  ColumnLayout get columns => _state.source.columns ?? _state.columns;

  @override
  bool get showHidden => _state.showHidden;

  @override
  Set<String> get marked => _state.marked;

  @override
  int get markedSize => _state.markedSize;

  @override
  bool get markedSizeIsFinal => _state.markedSizeIsFinal;

  // --- курсор ---

  /// Сколько строк помещается в видимой части списка; от этого считается шаг
  /// страницей. Значение выставляет таблица и на ту сторону оно не едет: шаг
  /// страницей — про показ, а список у этой стороны на руках.
  @override
  int pageSize = 20;

  @override
  int get cursorIndex => _state.cursorIndex;

  @override
  FileEntry? get currentEntry =>
      _state.cursorIndex >= 0 && _state.cursorIndex < entries.length ? entries[_state.cursorIndex] : null;

  @override
  void moveCursor(int delta) => setCursorIndex(_state.cursorIndex + delta);

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

  @override
  bool isMarked(FileEntry entry) => _state.marked.contains(entry.name);

  @override
  void setMarks(Set<String> names) {
    _state = _state.copyWith(marked: names);
    _link.tell(SetMarks(id, names));
    notifyListeners();
  }

  @override
  void mark(FileEntry entry) => setMarks({..._state.marked, entry.name});

  @override
  void unmark(FileEntry entry) => setMarks({..._state.marked}..remove(entry.name));

  @override
  void markAll() => setMarks({
    for (final entry in entries)
      if (!entry.isParent) entry.name,
  });

  @override
  void clearMarks() => setMarks(const {});

  /// Пометить объект под курсором и сдвинуть курсор вниз.
  ///
  /// Одной просьбой: пометка и курсор здесь — одно действие, и разложить его
  /// на две значило бы разрешить им разъехаться.
  @override
  void toggleCurrentMark() => _link.tell(ToggleMark(id));

  /// Помеченное, а если не помечено ничего — объект под курсором.
  ///
  /// То самое правило, по которому работают все файловые операции.
  @override
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

  @override
  void setStatusText(String? text) {
    if (_state.statusText == text) {
      return;
    }
    _state = _state.copyWith(statusText: text, clearStatus: text == null);
    _link.tell(SetStatusText(id, text));
    notifyListeners();
  }

  @override
  void setHeaderText(String? text) {
    if (_state.headerText == text) {
      return;
    }
    _state = _state.copyWith(headerText: text, clearHeader: text == null);
    _link.tell(SetHeaderText(id, text));
    notifyListeners();
  }

  // --- переходы ---

  /// Чужая работа уступает место переходу.
  ///
  /// Правило то же, что и у ядра: последнее сказанное человеком главнее. Ядро
  /// прерывает своё, а своё — здесь, и прервать его больше некому.
  void _yieldWork() => _work?.cancel();

  @override
  Future<bool> openPath(String path, {bool allowConnect = true}) async {
    _yieldWork();
    final reply = await _link.call(OpenPath(id, path, allowConnect: allowConnect));
    return reply is CoreOpened && reply.opened;
  }

  /// Войти в строку списка. Возвращает то, во что войти нельзя; null — вошли.
  @override
  Future<FileEntry?> enter(FileEntry entry) async {
    _yieldWork();
    final index = entries.indexOf(entry);
    if (index < 0) {
      return null;
    }
    final reply = await _link.call(OpenEntry(id, EntryRef.inPanel(id, index, _listing.generation)));
    return reply is CoreEntered ? reply.entry : null;
  }

  @override
  Future<FileEntry?> enterCurrent() async {
    final current = currentEntry;
    return current == null ? null : enter(current);
  }

  @override
  Future<void> goUp() {
    _yieldWork();
    return _link.call(GoUp(id));
  }

  @override
  Future<void> reload() {
    _yieldWork();
    return _link.call(Reload(id));
  }

  /// Прервать то, чем панель занята, — по обе стороны.
  ///
  /// Своя работа идёт здесь, ядровая — там, а `Esc` у человека один. Сказать
  /// мёртвому — тишина, а не ошибка, поэтому говорим обоим.
  @override
  void cancel() {
    _work?.cancel();
    _link.tell(CancelWork(id));
  }

  @override
  void measureDirectories() => _link.tell(MeasureDirectories(id));

  // --- вид ---

  @override
  Future<void> sortBy(FsColumn column) {
    if (!column.sortable) {
      return Future.value();
    }
    return _link.call(Arrange(id, sort: _state.sort.toggled(column)));
  }

  @override
  Future<void> setColumnLayout(ColumnLayout layout) => _link.call(Arrange(id, columns: layout));

  @override
  Future<void> setShowHidden(bool value) => _link.call(Arrange(id, showHidden: value));

  // --- своя работа ---

  /// Работа, которую ведёт экран; null — панель занята чем-то ядровым или
  /// свободна.
  Operation<void, Object?>? _work;
  String? _workStatus;

  @override
  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String status = 'Loading…'}) async {
    final operation = TaskOperation<void, R>((op, _) => body(op));

    // Прежняя работа уступает место, а не отказывает новой: правило то же, что
    // у чтения каталога, — последнее сказанное человеком главнее.
    _work?.cancel();

    _work = operation;
    _workStatus = status;
    // Ядру говорим той же строкой: его половина состояния должна сходиться с
    // нашей, иначе следующее же `PanelChanged` сотрёт наш рассказ о себе.
    _link.tell(SetStatusText(id, status));
    // Ход дела работы — та же строка состояния: человек видит, чем занята
    // панель, а не просто что она занята.
    void onProgress() {
      final message = operation.status.message;
      if (message.isEmpty || !identical(_work, operation)) {
        return;
      }
      _workStatus = message;
      _link.tell(SetStatusText(id, message));
      notifyListeners();
    }

    operation.status.addListener(onProgress);
    notifyListeners();

    operation.start(null);
    try {
      return await operation.result;
    } finally {
      operation.status.removeListener(onProgress);
      // Занятость снимается чем бы дело ни кончилось — иначе панель осталась бы
      // глухой к клавиатуре навсегда. Но только если за это время не началась
      // работа поновее: строка состояния и занятость теперь её.
      if (identical(_work, operation)) {
        // Сперва ядру, потом себе: эхо придёт, пока работа ещё «наша», и
        // занятость в нём не провалится в `false` раньше времени — а провал
        // между звеньями цепочки виден человеку миганием.
        _link.tell(SetStatusText(id, null));
        _work = null;
        _workStatus = null;
      }
      notifyListeners();
    }
  }

  // --- содержимое ---

  @override
  Content contentOf(FileEntry entry) {
    final ref = _refTo(entry);
    return ref == null ? const NoContent() : RemoteContent(_link, ref, length: entry.size);
  }

  @override
  Future<bool> canWriteTo(FileEntry entry) async {
    final ref = _refTo(entry);
    if (ref == null) {
      return false;
    }
    final reply = await _link.call(CheckWriteAccess(ref));
    return reply is CoreFlag && reply.value;
  }

  /// Ссылка на строку: место в списке и его номер.
  EntryRef? _refTo(FileEntry entry) {
    final index = entries.indexWhere((candidate) => candidate.name == entry.name);
    return index < 0 ? null : EntryRef.inPanel(id, index, _listing.generation);
  }

  // --- область ---

  @override
  String get directoryName => _state.directoryName;

  @override
  bool get canGoUp => _state.canGoUp;

  @override
  bool get active => _active;
  bool _active = false;

  /// Только для `AppController`: активной должна быть ровно одна панель.
  ///
  /// Остаётся на этой стороне: активность — это про то, кому принадлежит ввод,
  /// а клавиатура есть только здесь.
  void setActive(bool value) {
    if (_active == value) {
      return;
    }
    _active = value;
    notifyListeners();
  }

  /// Фокус панелям не нужен: какая область активна, знает приложение, а
  /// нажатия разбирает ранний обработчик клавиатуры.
  @override
  bool get takesKeyboard => false;

  /// Панель убрали из области: своё бросаем здесь, ядровое — просьбой.
  ///
  /// Ядру сказать обязательно: архив, смонтированный ради этой панели, держать
  /// больше незачем, а знает об этом только оно.
  @override
  void close() {
    _work?.cancel();
    _link.tell(ClosePanel(id));
  }

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
    _work?.cancel();
    unawaited(_events.cancel());
    super.dispose();
  }
}
