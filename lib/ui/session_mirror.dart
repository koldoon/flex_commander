import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import '../link/link.dart';
import '../state/column_registry.dart';
import 'remote_content.dart';

/// Сессия со стороны экрана: зеркало того, что держит ядро.
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
class SessionMirror extends ChangeNotifier implements Session {
  SessionMirror({
    required this.id,
    required Link link,
    required PanelState state,
    required PanelListing listing,
    PanelColumns columns = const NoPanelColumns(),
    Strings? strings,
  }) : _link = link,
       _declared = columns,
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

  /// Объявленные колонки: раскладку из настроек накладывают на них здесь —
  /// реестр живёт по эту сторону границы (`docs/spec/column-registry.md`, §4).
  final PanelColumns _declared;
  final Strings _strings;
  late final StreamSubscription<CoreEvent> _events;

  PanelState _state;
  PanelListing _listing;

  /// Строка, на которой стоит курсор, — **путём**.
  ///
  /// Курсор живёт здесь, но список приходит из ядра и меняется: прирост
  /// находок, догоняющее чтение, перечитывание. Номер в новом списке означал
  /// бы другую строку, поэтому своё место держится путём и ищется заново.
  /// Пусто — строку не опознать (список пуст, курсор на «..»), и тогда
  /// остаётся номер.
  String _cursorPath = '';

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

  /// Раскладка, разобранная в прошлый раз, и то, из чего она разобрана.
  ///
  /// Спрашивают её на каждую сборку списка, а собирается она заново с новыми
  /// `ColumnSpec` — и строка получала новые приметы там, где ничего не менялось
  /// (`docs/spec/panel-redraw.md`, §4).
  ColumnLayout? _resolved;
  ColumnLayout? _resolvedFrom;
  Set<String>? _resolvedExtra;

  @override
  ColumnLayout get columns {
    final saved = _state.columns;
    final extra = _state.source.extraColumns;
    // По экземпляру: состояние приезжает целиком и заменяется целиком, а
    // раскладка внутри него неизменяема.
    if (_resolved case final ready? when identical(_resolvedFrom, saved) && identical(_resolvedExtra, extra)) {
      return ready;
    }
    _resolvedFrom = saved;
    _resolvedExtra = extra;
    return _resolved = _declared.resolve(saved, extra: extra);
  }

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
  PanelSteps cursorSteps = const PanelSteps.list();

  @override
  /// Где стоит курсор — **здесь**, а не в состоянии панели: курсор
  /// принадлежит этой стороне, и ядро о нём ничего не решает
  /// (`docs/spec/client-server.md`, §5.6).
  @override
  int get cursorIndex => _cursorIndex;

  int _cursorIndex = 0;

  @override
  FileEntry? get currentEntry => _cursorIndex >= 0 && _cursorIndex < entries.length ? entries[_cursorIndex] : null;

  @override
  void moveCursor(int delta) => setCursorIndex(_cursorIndex + delta);

  @override
  void moveCursorPage(int direction) {
    // Страница — целое число рядов там, где ряды есть: иначе единица
    // перекрытия, взятая ради «строка со стыка остаётся на виду», уводила бы
    // курсор на плитку вбок за каждую страницу
    // (`docs/spec/panel-view-icons.md`, §6). При обычном шаге в строку это
    // ровно прежнее поведение.
    final step = (pageSize - 1).clamp(1, pageSize);
    final rows = cursorSteps.down;
    moveCursor(direction * (rows > 1 ? (step ~/ rows) * rows : step).clamp(1, pageSize));
  }

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

  /// Поставить курсор на строку с этим путём.
  ///
  /// Своим телом, а не через [setCursorIndex]: путь тут главнее номера. Так
  /// курсор двигает вид, который **сам меняет список** (столбцы): номер строки
  /// у него может не измениться вовсе, а строка — другая, в соседнем столбце.
  @override
  void setCursorToPath(String path) {
    final index = entries.indexWhere((entry) => entry.path == path);
    if (index < 0) {
      return;
    }
    _cursorPath = path;
    _cursorIndex = index;
    notifyListeners();
    _link.tell(CursorAt(id, path));
  }

  /// Курсор ставится **здесь и окончательно**: он принадлежит этой стороне.
  ///
  /// Ядру уходит факт — «стоим вот на этой строке», — и ответа на него нет.
  /// Ядро знает о курсоре ровно столько, сколько ему сказали, и обратно его не
  /// присылает: эха нет, спорить некому (`docs/spec/client-server.md`, §5.6).
  @override
  void setCursorIndex(int index) {
    final clamped = entries.isEmpty ? 0 : index.clamp(0, entries.length - 1);
    if (clamped == _cursorIndex) {
      return;
    }
    // Строка запоминается **путём**: список могут сменить, и номер в новом
    // будет означать другую строку.
    _rememberCursor(clamped);
    _cursorIndex = clamped;
    notifyListeners();
    // Факт уходит **сразу**, а не с ближайшим кадром: следом за шагом курсора
    // идёт заявка, которой это место и нужно — сменить вид на дерево,
    // скопировать «туда, где стоит соседка», записать шаг истории. Придержанный
    // факт такая заявка обгоняет, и ядро отвечает по вчерашней строке.
    // Дорого это не стоит: сообщение крошечное, ответа у него нет, а взамен
    // ушло состояние панели, которое ездило на каждый шаг.
    _link.tell(CursorAt(id, _cursorPath));
  }

  // --- пометка ---

  /// Помечен ли объект — **путём**: у «..» пути нет, и помеченным он не бывает.
  @override
  bool isMarked(FileEntry entry) => entry.path.isNotEmpty && _state.markedPaths.contains(entry.path);

  @override
  void setMarks(Set<String> paths, {MarkChange by = MarkChange.person}) {
    _marksSeq++;
    _state = _state.copyWith(markedPaths: paths, marksSeq: _marksSeq);
    _link.tell(SetMarks(id, paths, _marksSeq, by: by));
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
  void clearMarks({required MarkChange by}) => setMarks(const {}, by: by);

  /// Пометить объект под курсором и сдвинуть курсор вниз.
  ///
  /// Целиком **здесь**: пометка и шаг — дело экрана, ядру едет только новая
  /// пометка. Отдельной просьбы «переключи и шагни» больше нет: пока она была,
  /// ядро решало по своему курсору, а он у него всегда отстающий
  /// (`docs/spec/client-server.md`, §5.6).
  @override
  void toggleCurrentMark({bool step = true}) {
    // Показываем только то, в чём уверены: «..» не помечается, а про строку
    // уровня 0 в дереве решает ядро (корень источника целью не бывает) — но
    // его отказ придёт пометкой, и своя догадка сама собой поправится.
    final entry = currentEntry;
    if (entry == null || entry.isParent || (rows.isTree && entry.level == 0)) {
      return;
    }

    final marks = {..._state.markedPaths};
    if (!marks.remove(entry.path)) {
      marks.add(entry.path);
    }
    // Пометка — обычной заменой набора: другой двери у неё нет, и правило
    // «набор меняется целиком» остаётся тем же (§5.5).
    setMarks(marks);
    if (step) {
      moveCursor(1);
    }
  }

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
        final sized = _withSizes(_listing);
        // Перерисовываем **только если в показанных строках и правда
        // изменилось**. Обход помечает размер каждого встреченного подкаталога,
        // а их в большом дереве десятки тысяч; из них в списке видны единицы, и
        // остальные вести до экрана доходить не должны. Живьём это выглядело
        // так: помечаешь каталог — интерфейс подвисает (разбор 17 сентября
        // 2026).
        if (!identical(sized, _listing)) {
          _listing = sized;
          notifyListeners();
        }
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
  /// Тот же объект, если ни одна показанная строка не изменилась: по нему
  /// сверяются те, кто считает раскладку (нарезка столбцов, закрепление
  /// строки), — и лишней работы не делают.
  PanelListing _withSizes(PanelListing listing) {
    List<FileEntry>? entries;
    for (var at = 0; at < listing.entries.length; at++) {
      final entry = listing.entries[at];
      final FileEntry? changed;
      if (_forgotten.contains(entry.path) && !entry.sizeIsFinal) {
        changed = entry.withSize(FileEntry.unknownSize);
      } else if (_sizes[entry.path] case final size?) {
        final isFinal = !_partial.contains(entry.path);
        changed = entry.size == size && entry.sizeIsFinal == isFinal ? null : entry.withSize(size, isFinal: isFinal);
      } else {
        changed = null;
      }
      if (changed != null) {
        entries ??= [...listing.entries];
        entries[at] = changed;
      }
    }
    _forgotten.clear();
    if (entries == null) {
      return listing;
    }
    return PanelListing(generation: listing.generation, entries: entries, cursor: listing.cursor);
  }

  /// Цели значениями — все, включая чужие каталоги: спрашиваются у ядра, где
  /// живут узлы.
  @override
  Future<List<FileEntry>> allTargets() async {
    final reply = await _link.call(ListTargets(id, under: currentRef));
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
    // «..» называется одной личностью: пути у неё нет, и подтверждать его
    // нечем — а войти в неё надо.
    final reply = await _link.call(OpenEntry(id, EntryRef.inPanel(id, entry.id, path: entry.path)));
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
  Future<void> sortBy(String column) {
    // Незнакомая и несортируемая колонки не делают ничего — как и в ядре, куда
    // эта заявка поехала бы.
    if (!(_declared.find(column)?.sortable ?? false)) {
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
  bool get sorted => _state.sorted;

  @override
  Future<void> setView(String view) => _link.call(Arrange(id, view: view));

  @override
  RowsKind get rows => _state.rows;

  @override
  Future<void> showRows(RowsKind kind) => _link.call(Arrange(id, rows: kind));

  @override
  @override
  void setExpanded(String path, {required bool expanded}) => _link.tell(ExpandRow(id, path, expanded: expanded));

  @override
  Future<bool> followLink(String path) async {
    final reply = await _link.call(FollowLink(id, path));
    return reply is CoreFlag && reply.value;
  }

  /// Раскрыть или свернуть вглубь — и узнать, чем кончилось.
  ///
  /// Просьбой с ответом, а не просто просьбой: упёршееся в предел раскрытие
  /// говорит об этом **тостом**, и сказать это может только тот, кто просил
  /// (`docs/spec/panel-view-tree.md`, §6а).
  @override
  Future<PanelExpansion> expandDeep(String path, {required bool expanded}) async {
    final reply = await _link.call(ExpandRow(id, path, expanded: expanded, deep: true));
    return reply is CoreExpanded
        ? PanelExpansion(opened: reply.opened, stopped: reply.stopped)
        : const PanelExpansion(opened: 0, stopped: false);
  }

  /// Прокрутка, о которой сказал вид; null — вид ещё ничего не говорил, и в
  /// ход идёт то, что приехало снимком (прошлый запуск).
  ///
  /// Своя, а не из снимка: снимок складывает ядро, и вернётся он **после**
  /// того, как ядро о прокрутке узнает. Вид между тем успевает собраться
  /// заново — после полноэкранного просмотра, например, — и прочитал бы
  /// вчерашнее число (`docs/spec/panel-views.md`, §10).
  double? _scroll;

  @override
  double get scrollOffset => _scroll ?? _state.scroll;

  @override
  void setScrollOffset(double offset) {
    _scroll = offset;
    // Ядру всё равно говорим: это оно складывает снимок, который переживёт
    // перезапуск.
    _link.tell(ScrollTo(id, offset));
  }

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

  /// Байты и атрибуты одной ручкой — тем, кто о строке рассказывает.
  @override
  NodeSource sourceOf(FileEntry entry) => _EntrySource(this, entry);

  @override
  Future<NodeAttributes> readAttributes(FileEntry entry) async {
    final ref = _refTo(entry);
    if (ref == null) {
      // У «..» пути нет, и спрашивать не о чем.
      return NodeAttributes.unknown;
    }
    final reply = await _link.call(ReadAttributes(ref));
    return switch (reply) {
      CoreAttributes(:final attributes) => attributes,
      // Отказ доходит до того, кто спросил: окно скажет, почему не вышло.
      CoreFailed(:final error) => throw error,
      _ => NodeAttributes.unknown,
    };
  }

  @override
  Future<bool> canWriteTo(FileEntry entry) async {
    final ref = _refTo(entry);
    if (ref == null) {
      return false;
    }
    final reply = await _link.call(CheckWriteAccess(ref));
    return switch (reply) {
      CoreFlag(:final value) => value,
      // Отказ доходит до того, кто спросил: «не нашли строку» — не то же, что
      // «писать не дают», и редактор различает их сам.
      CoreFailed(:final error) => throw error,
      _ => true,
    };
  }

  /// Ссылка на строку: её личность и путь при ней.
  ///
  /// Личность выдало ядро вместе со списком, и по ней оно найдёт **тот самый**
  /// узел, даже если список с тех пор дорос (`docs/spec/client-server.md`,
  /// §5.5а). Путь едет рядом — им подтверждают личность и им же выручают, когда
  /// каталог перечитали и номера сменились.
  ///
  /// Строки из чужих рук (перетаскивание, сценарий) личности не имеют — их
  /// называют адресом, и разбирать его ядро умеет.
  /// Строка под курсором — ссылкой, какой её называют ядру.
  ///
  /// Курсор принадлежит экрану, и всякий, кому нужна «та строка, на которой
  /// стоит человек», получает её отсюда — а не просит ядро посмотреть у себя
  /// (`docs/spec/client-server.md`, §5.6).
  @override
  EntryRef? get currentRef {
    final entry = currentEntry;
    return entry == null || entry.isParent ? null : _refTo(entry);
  }

  EntryRef? _refTo(FileEntry entry) {
    if (entry.path.isEmpty) {
      // Путь есть у всего, кроме «..», а её читать нечем.
      return null;
    }
    return entry.id == 0 ? EntryRef.path(entry.path) : EntryRef.inPanel(id, entry.id, path: entry.path);
  }

  // --- область ---

  @override
  String get directoryName => _state.directoryName;

  @override
  bool get canGoUp => _state.canGoUp;

  @override
  bool get canGoBack => _state.canGoBack;

  @override
  bool get canGoForward => _state.canGoForward;

  @override
  Future<void> goBack() => _link.call(WalkHistory(id, HistoryWalk.back));

  @override
  Future<void> goForward() => _link.call(WalkHistory(id, HistoryWalk.forward));

  @override
  Future<void> goToStep(int index) => _link.call(WalkHistory(id, HistoryWalk.toStep, index: index));

  @override
  Future<({List<PathStep> steps, int index})> history() async {
    final reply = await _link.call(AskHistory(id));
    return reply is CoreHistory ? (steps: reply.steps, index: reply.index) : (steps: const <PathStep>[], index: -1);
  }

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

  /// Где в **нынешнем** списке стоит запомненная строка; нет такой — прежний
  /// номер: объект исчез, и ронять курсор на случайного соседа хуже, чем
  /// оставить его на месте.
  int get _cursorIndexNow {
    if (_cursorPath.isEmpty) {
      return _cursorIndex;
    }
    final at = entries.indexWhere((entry) => entry.path == _cursorPath);
    return at < 0 ? _cursorIndex : at;
  }

  /// Запомнить строку под курсором — ту, что стоит по этому номеру сейчас.
  void _rememberCursor(int index) {
    _cursorPath = index >= 0 && index < entries.length ? entries[index].path : '';
  }

  void _apply(CoreEvent event) {
    switch (event) {
      case PanelChanged(:final panel, :final state) when panel == id:
        // Курсор и пометка берутся из ответа только если он про нашу
        // последнюю заявку: опоздавший вернул бы курсор назад, а пометку —
        // отобрал.
        // Курсор из состояния **не берётся вовсе**: он принадлежит этой
        // стороне. Ядро присылает своё представление о нём по привычке — оно
        // уйдёт из состояния следующим шагом, — и слушать его значит вернуть
        // то самое эхо, ради которого всё затевалось
        // (`docs/spec/client-server.md`, §5.6).
        var next = state;
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
        // Ядро поставило курсор нарочно — список сменился по нашей же просьбе
        // (вошли, поднялись, раскрыли ветвь, поднялись после запуска). Он
        // приехал **вместе со списком**, к которому относится, и потому
        // применяется сразу и без оглядки на номера
        // (`docs/spec/client-server.md`, §5.6.4).
        final placed = listing.cursor.isEmpty ? -1 : listing.entries.indexWhere((e) => e.path == listing.cursor);
        if (placed >= 0) {
          _cursorIndex = placed;
          _rememberCursor(placed);
        } else {
          // Список сменился сам по себе — курсор ищет в нём **свою строку**:
          // человека, пошедшего по списку, прирост находок с места не сдвигает
          // (§5.6.4).
          _cursorIndex = _cursorIndexNow;
        }
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

/// Строка как источник сведений о себе.
///
/// Значением, а не парой замыканий: спрашивают о ней и байты, и атрибуты, и
/// завтра — контрольную сумму; носить их порознь пришлось бы всем по дороге.
class _EntrySource implements NodeSource {
  const _EntrySource(this._panel, this._entry);

  final SessionMirror _panel;
  final FileEntry _entry;

  @override
  Content get content => _panel.contentOf(_entry);

  @override
  Future<NodeAttributes> attributes() => _panel.readAttributes(_entry);
}
