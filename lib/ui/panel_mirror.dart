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
  PanelMirror({
    required this.id,
    required Link link,
    required PanelState state,
    required PanelListing listing,
    Strings? strings,
  }) : _link = link,
       _state = state,
       _listing = listing,
       // Своя работа тоже рассказывает о себе — и на языке человека. Своих
       // строк нет — значит английские, как в коде.
       _strings = strings ?? StringsRegistry() {
    _events = link.events.listen(_apply);
  }

  @override
  final PanelId id;

  final Link _link;
  final Strings _strings;
  late final StreamSubscription<CoreEvent> _events;

  PanelState _state;
  PanelListing _listing;

  /// Номер последней **своей** заявки на курсор.
  ///
  /// Подтверждение с меньшим номером — опоздавшее: пока оно шло, человек успел
  /// нажать стрелку ещё раз, и слушать его значит дёргать курсор назад.
  int _cursorSeq = 0;

  /// Номер последней **своей** заявки на пометку — по той же причине, что и у
  /// курсора: пометка ставится сразу, а подтверждения на первые заявки приходят,
  /// когда помечено уже больше. Зажатый `Space` в дереве этим и отличается от
  /// одиночного нажатия.
  int _marksSeq = 0;

  PanelState get state => _state;

  /// Список, каким его показывает зеркало сейчас. Нужен проверкам: собрать
  /// второе зеркало на том же месте, где стоит это.
  PanelListing get listing => _listing;

  @override
  List<FileEntry> get entries => _listing.entries;

  @override
  SourceInfo get source => _state.source;

  @override
  String get currentPath => _state.currentPath;

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
  Set<String> get markedPaths => _state.markedPaths;

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

  /// Столбцов у таблицы нет; вид, который ими раскладывает, скажет своё.
  @override
  int columnRows = 0;

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

  /// Помечен ли объект — **путём**: у «..» пути нет, и помеченным он не бывает.
  @override
  bool isMarked(FileEntry entry) => entry.path.isNotEmpty && _state.markedPaths.contains(entry.path);

  @override
  void setMarks(Set<String> paths) {
    _marksSeq++;
    _state = _state.copyWith(markedPaths: paths, marksSeq: _marksSeq);
    _link.tell(SetMarks(id, paths, _marksSeq));
    notifyListeners();
  }

  /// «..» не помечается никогда — пути у него нет вовсе.
  @override
  void mark(FileEntry entry) {
    if (entry.isParent) {
      return;
    }
    setMarks({..._state.markedPaths, entry.path});
  }

  @override
  void unmark(FileEntry entry) => setMarks({..._state.markedPaths}..remove(entry.path));

  @override
  void markAll() => setMarks({
    for (final entry in entries)
      if (!entry.isParent) entry.path,
  });

  @override
  void clearMarks() => setMarks(const {});

  /// Пометить объект под курсором и сдвинуть курсор вниз.
  ///
  /// Одной просьбой: пометка и курсор здесь — одно действие, и разложить его
  /// на две значило бы разрешить им разъехаться.
  @override
  void toggleCurrentMark({bool step = true}) => _link.tell(ToggleMark(id, step: step));

  /// Помеченное, а если не помечено ничего — объект под курсором.
  ///
  /// Строками, а значит **только своего каталога**: помеченное в другой ветви
  /// дерева у этой стороны значением не лежит вовсе. Так и задумано — строку
  /// рисуют и тянут мышью, а для этого нужен видимый объект. Кому нужны все
  /// цели, тот зовёт [allTargets] (`docs/spec/operation-targets.md`, §4).
  @override
  List<FileEntry> get targets {
    if (_state.markedPaths.isEmpty) {
      final current = currentEntry;
      return current == null || current.isParent ? const [] : [current];
    }
    return [
      for (final entry in entries)
        if (_state.markedPaths.contains(entry.path)) entry,
    ];
  }

  /// Пути всех целей — они приезжают полными, где бы цели ни лежали.
  ///
  /// Отсюда счёт в заголовках окон: ходить за границу ради числа значило бы
  /// задерживать окно ради того, что уже в руках
  /// (`docs/spec/operation-targets.md`, §2).
  @override
  Set<String> get targetPaths {
    if (_state.markedPaths.isNotEmpty) {
      return _state.markedPaths;
    }
    // У «..» пути нет вовсе — и целью он не бывает.
    final current = currentEntry;
    return current == null || current.path.isEmpty ? const {} : {current.path};
  }

  @override
  bool get hasTargets => targetPaths.isNotEmpty;

  /// Посчитанные размеры каталогов по путям — то, что панель успела узнать.
  ///
  /// Одно место на всех: и строки списка, и ветви дерева берут число отсюда.
  /// Раньше их было два — числа в списке и ответ на вопрос через границу, — и
  /// на быстром обходе они расходились: значение прыгало между свежим и
  /// вчерашним.
  final Map<String, int> _sizes = {};

  /// Пути, о которых сказали «изменилось», а значение ещё не спрошено.
  final Set<String> _stale = {};

  /// Пути, чьё число — половина: обход идёт.
  final Set<String> _partial = {};

  /// Пути, о которых ядро больше не знает: строке пора вернуть прочерк.
  final Set<String> _forgotten = {};

  /// Вопрос в пути: второго, пока не ответили, не будет.
  bool _pulling = false;

  /// Спрашивает значения для накопившихся путей — по одному вопросу за раз.
  ///
  /// Пока вопрос в пути, новые пути копятся и уходят следующим — одним. Отсюда
  /// главное свойство: сколько бы сообщений ни пришло, оборотов через границу
  /// не больше, чем успевает сделать сама граница, а показанное число всегда
  /// то, какое ядро знает **на миг ответа**. Гонка тут безвредна: худшее, что
  /// бывает, — лишняя перерисовка.
  void _pullSizes() {
    if (_pulling || _stale.isEmpty) {
      return;
    }
    final asked = List.of(_stale);
    _stale.clear();
    _pulling = true;
    unawaited(
      _link.call(AskSizes(id, asked)).then((reply) {
        _pulling = false;
        final answer = reply is CoreSizes ? reply : const CoreSizes({});
        for (final path in asked) {
          final size = answer.sizes[path];
          if (size == null) {
            // Ядро о нём больше не знает: обход оборвали или каталог
            // перечитали. Частичная сумма, застывшая в колонке, — ложь, и
            // строке возвращается прочерк.
            _sizes.remove(path);
            _forgotten.add(path);
          } else {
            _sizes[path] = size;
            _forgotten.remove(path);
            if (answer.partial.contains(path)) {
              _partial.add(path);
            } else {
              _partial.remove(path);
            }
          }
        }
        _listing = _withSizes(_listing);
        notifyListeners();
        // Пока спрашивали, могло накопиться ещё.
        _pullSizes();
      }),
    );
  }

  @override
  int? sizeOf(String path) => _sizes[path];

  /// Тот же список, но с числами из карты — после свежих чисел о путях.
  ///
  /// Забытое ядром возвращается к прочерку: половина, застывшая в колонке,
  /// хуже пустоты.
  PanelListing _withSizes(PanelListing listing) {
    final entries = [
      for (final entry in listing.entries)
        if (_forgotten.contains(entry.path) && !entry.sizeIsFinal)
          entry.withSize(FileEntry.unknownSize)
        else if (_sizes[entry.path] case final size?)
          entry.withSize(size, isFinal: !_partial.contains(entry.path))
        else
          entry,
    ];
    _forgotten.clear();
    return PanelListing(generation: listing.generation, entries: entries);
  }

  /// Цели значениями — все, включая чужие каталоги: спрашиваются у ядра, где
  /// живут узлы.
  @override
  Future<List<FileEntry>> allTargets() async {
    final reply = await _link.call(ListTargets(id));
    return reply is CoreEntries ? reply.entries : const [];
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

  /// Идти за курсором вида: показать каталог, не открывая его.
  ///
  /// Просьбой без ответа (`tell`), а не вызовом: за курсором дерева это делается
  /// на каждую стрелку, и ждать оборота границы тут нечего — плашка сменится
  /// тем же событием, каким ядро расскажет о новом каталоге
  /// (`docs/spec/panel-view-tree.md`, §3).
  ///
  /// Свою работу переход не прерывает: это ход курсора, а не уход человека.
  @override
  void follow(String directory, {String name = ''}) => _link.tell(FollowCursor(id, directory, name));

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

  @override
  String get view => _state.view;

  @override
  Future<void> setView(String view) => _link.call(Arrange(id, view: view));

  @override
  RowsKind get rows => _state.rows;

  @override
  Future<void> showRows(RowsKind kind) => _link.call(Arrange(id, rows: kind));

  @override
  void setExpanded(String path, {required bool expanded}) => _link.tell(ExpandRow(id, path, expanded: expanded));

  @override
  double get scrollOffset => _state.scroll;

  @override
  void setScrollOffset(double offset) => _link.tell(ScrollTo(id, offset));

  // --- своя работа ---

  /// Работа, которую ведёт экран; null — панель занята чем-то ядровым или
  /// свободна.
  Operation<void, Object?>? _work;
  String? _workStatus;

  @override
  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String? status}) async {
    final operation = TaskOperation<void, R>((op, _) => body(op));
    final said = status ?? _strings.tr('Loading…');

    // Прежняя работа уступает место, а не отказывает новой: правило то же, что
    // у чтения каталога, — последнее сказанное человеком главнее.
    _work?.cancel();

    _work = operation;
    _workStatus = said;
    // Ядру говорим той же строкой: его половина состояния должна сходиться с
    // нашей, иначе следующее же `PanelChanged` сотрёт наш рассказ о себе.
    _link.tell(SetStatusText(id, said));
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
  ///
  /// Место ищется **по пути**, а не по имени: цели бывают из других каталогов,
  /// а одноимённая строка своего каталога — это другой файл, и прочитать вместо
  /// спрошенного его было бы подменой (`docs/spec/operation-targets.md`, §4).
  /// Не нашлось здесь — говорим адресом: разбирать пути ядро умеет.
  EntryRef? _refTo(FileEntry entry) {
    if (entry.path.isEmpty) {
      // Путь есть у всего, кроме «..», а его читать нечем.
      return null;
    }
    final index = entries.indexWhere((candidate) => candidate.path == entry.path);
    return index < 0 ? EntryRef.path(entry.path) : EntryRef.inPanel(id, index, _listing.generation);
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
        // Курсор и пометка берутся из ответа только если он про нашу
        // последнюю заявку: опоздавший вернул бы курсор назад, а пометку —
        // отобрал.
        var next = state;
        if (state.cursorSeq < _cursorSeq) {
          next = next.copyWith(cursorIndex: _state.cursorIndex, cursorSeq: _cursorSeq);
        }
        if (state.marksSeq < _marksSeq) {
          next = next.copyWith(markedPaths: _state.markedPaths, marksSeq: _marksSeq);
        }
        _state = next;
        notifyListeners();

      case PanelListed(:final panel, :final listing) when panel == id:
        // Список собран ядром **сейчас**, и числа в нём свежее карты — значит
        // не он подчиняется карте, а карта ему. Иначе строка шагала бы назад:
        // карта отстаёт ровно на то, что придерживает ограничитель
        // перерисовки.
        for (final entry in listing.entries) {
          if (entry.size >= 0) {
            _sizes[entry.path] = entry.size;
          }
        }
        _listing = listing;
        notifyListeners();

      case PanelSized(:final panel, :final paths) when panel == id:
        // Событие говорит только «здесь изменилось». Значение спросим сами —
        // к этому мигу обход уже ушёл вперёд.
        _stale.addAll(paths);
        _pullSizes();

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
