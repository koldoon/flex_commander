import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'search_address.dart';
import 'search_limits.dart';
import 'search_query.dart';
import 'search_work.dart';

/// Состояние окна поиска: о чём спросили, что нашлось и идёт ли обход.
class FindFilesState extends ChangeNotifier {
  FindFilesState({required this.app, required this.panel, required this.where, required this.runId});

  final Application app;

  /// Имя этой работы в реестре: у каждого поиска своё, их может идти сколько
  /// угодно — ровно как копирований.
  final String runId;

  /// Панель, в каталоге которой ищут и в которую отдают найденное.
  final Session panel;

  /// Где искать — путём. Не поле окна: чтобы искать в другом месте, туда
  /// переходят панелью, — так не бывает поиска «не там, где думает человек».
  final String where;

  SearchQuery query = const SearchQuery(mask: '');

  /// Вкладка с находками — та, в которой смонтирован источник.
  ///
  /// Список принадлежит **ей**, а окно его только показывает: держать у себя
  /// второй значило бы завести второго владельца, а на стыках владельцев всё и
  /// разваливалось (`docs/spec/file-search.md`, §4.7).
  Panel? get tab => _tab;
  Panel? _tab;

  /// Сессия вкладки: её же рисует окно, её же получит панель.
  Session? get results => _tab?.session;

  /// Адрес запроса; null — ещё не искали.
  SearchAddress? get address => _address;
  SearchAddress? _address;

  /// Сколько нашлось. Считается по ходу — сами находки живут в источнике.
  int get foundCount => _foundCount;
  int _foundCount = 0;

  /// Перерисовка не чаще, чем имеет смысл смотреть.
  ///
  /// Находки приходят по одной и быстрее, чем экран успевает обновиться:
  /// уведомление на каждую означало перерисовку окна на каждый файл, а вместе
  /// с ней — сборку всего списка заново. Отсюда и «зависло»: работа шла, но
  /// кадров между ней не оставалось.
  late final Throttle _redraw = Throttle(notifyListeners);

  /// Где обход сейчас; пусто — не идёт.
  String get at => _at;
  String _at = '';

  bool get busy => _run != null;
  Operation<OperationSpec, void>? _run;

  /// Искали хоть раз: до первого поиска «ничего не нашлось» — не ответ, а
  /// молчание.
  bool get searched => _searched;
  bool _searched = false;

  /// Крючки окон: показать параметры, показать находки, закрыть текущее.
  ///
  /// Ставит их тот, кто окна показывает, — состояние их только дёргает. Так же
  /// здесь и раньше жило `close`: строить окна — не дело состояния, а решать,
  /// когда какое, — его.
  VoidCallback? showParams;
  VoidCallback? showResults;
  VoidCallback? close;

  /// Строка под курсором — та же, что и в панели: курсор один на список.
  FileEntry? get current => results?.currentEntry;

  /// Есть куда перейти: под курсором находка, а не ветвь и не «..».
  bool get canGoTo {
    final entry = current;
    return entry != null && !entry.isParent && entry.scheme != SearchAddress.scheme && entry.directoryPath.isNotEmpty;
  }

  /// Есть что искать: маска непустая и обход не идёт.
  bool get canStart => !busy && !query.isEmpty && query.isValid && _limits.isValid;

  /// Разбор набранного в полях размера и даты.
  ///
  /// Числа и даты живут **строками** ровно до `OK`: пока человек печатает,
  /// половина набранного не разбирается, и негодное значение — это не ошибка
  /// ввода, а ещё не дописанное. Ошибку показывают у поля, а `OK` не даётся
  /// (`docs/spec/file-search.md`, §10.5).
  SearchLimits get limits => _limits;
  SearchLimits _limits = const SearchLimits();

  /// `OK` в окне параметров: закрыть его, показать находки и пойти искать.
  ///
  /// Порядок именно такой. Окно параметров закрывается **до** запуска: обход
  /// начинает рассказывать о себе с первого же каталога, и рассказывать ему
  /// должно уже второму окну.
  Future<void> begin() async {
    if (query.isEmpty) {
      return;
    }
    close?.call();
    showResults?.call();
    await start();
  }

  /// `Again`: назад к параметрам, с прежними значениями.
  ///
  /// Идущий обход при этом прекращается: спрашивать заново — значит искать
  /// заново, и держать старую работу не за чем.
  void again() {
    stop();
    app.operations.forget(runId);
    close?.call();
    showParams?.call();
  }

  /// Окно уходит, работа остаётся: полоска под панелью-источником.
  ///
  /// Убрать окно — дело того, кто его показал (`Operations.sendToBackground`),
  /// поэтому здесь оба действия рядом.
  void toBackground() {
    app.operations.sendToBackground(runId, owner: app.view.sourceArea);
    close?.call();
  }

  /// `Close`: окно, работа и вкладка уходят вместе.
  ///
  /// Вкладка тоже: человек сказал, что искомое ему больше не нужно, — а
  /// оставить её значило бы оставить список, за которым он не придёт.
  void finish() {
    stop();
    app.operations.forget(runId);
    final tab = _tab;
    _tab = null;
    if (tab != null) {
      app.closePanel(tab);
    }
    close?.call();
  }

  /// Что делает `Enter` в окне находок: идти к выбранной.
  ///
  /// Отдаётся это окну ([DialogSpec.onSubmit]), потому что `Enter` в открытом
  /// окне разбирает рама, а не поле ввода.
  Future<void> submit() async {
    if (canGoTo) {
      await goTo();
    }
  }

  /// Курсор ведёт сессия: список один, и второго курсора у него быть не может.
  void moveCursor(int delta) => results?.moveCursor(delta);

  void moveCursorPage(int direction) => results?.moveCursorPage(direction);

  void cursorToFirst() => results?.setCursorToFirst();

  void cursorToLast() => results?.setCursorToLast();

  /// Взять запрос из адреса — того, что панель уже показывает.
  ///
  /// Панель, оставленную в находках, приложение восстанавливает списком: он
  /// пуст, потому что обход при запуске никто не заводит (§4.6). Тогда
  /// `Alt-F7` из неё открывает окно **с тем же запросом** — повторить поиск
  /// становится делом одного `Enter`.
  void restore(SearchAddress address) {
    query = address.query;
    _limits = address.limits;
    notifyListeners();
  }

  void typed(String mask) {
    query = query.copyWith(mask: mask);
    notifyListeners();
  }

  void setRegexp(bool value) {
    query = query.copyWith(regexp: value);
    notifyListeners();
  }

  void setCaseSensitive(bool value) {
    query = query.copyWith(caseSensitive: value);
    notifyListeners();
  }

  void setIgnore(String value) {
    query = query.copyWith(ignore: value);
    notifyListeners();
  }

  void setFollowLinks(bool value) {
    query = query.copyWith(followLinks: value);
    notifyListeners();
  }

  /// Набранное в полях размера и даты — строками, как набрано.
  void setLimits(SearchLimits value) {
    _limits = value;
    query = query.copyWith(
      sizeFrom: () => value.sizeFrom,
      sizeTo: () => value.sizeTo,
      changedAfter: () => value.changedAfter,
      changedBefore: () => value.changedBefore,
    );
    notifyListeners();
  }

  void setContent(String value) {
    query = query.copyWith(content: value);
    notifyListeners();
  }

  /// Выражение и «любые кодировки» не сочетаются: выражение по неизвестной
  /// кодировке не значит ничего, и включённое гасит другое
  /// (`docs/spec/file-search.md`, §11.4).
  void setContentRegexp(bool value) {
    query = query.copyWith(contentRegexp: value, allCharsets: value ? false : null);
    notifyListeners();
  }

  void setContentCase(bool value) {
    query = query.copyWith(contentCase: value);
    notifyListeners();
  }

  void setWholeWords(bool value) {
    query = query.copyWith(wholeWords: value);
    notifyListeners();
  }

  void setAllCharsets(bool value) {
    query = query.copyWith(allCharsets: value, contentRegexp: value ? false : null);
    notifyListeners();
  }

  void setRecursive(bool value) {
    query = query.copyWith(recursive: value);
    notifyListeners();
  }

  void setHidden(bool value) {
    query = query.copyWith(hidden: value);
    notifyListeners();
  }

  /// Начать обход.
  ///
  /// Порядок: адрес → вкладка → работа. Вкладка заводится **обычным способом**
  /// и сразу показывается: окно в этот миг сверху, и появившаяся за ним вкладка
  /// никого не тревожит (`docs/spec/file-search.md`, §4.3). Работу заводит
  /// экран — правило «работа рождается заявкой с экрана» поиск не отменяет.
  Future<void> start() async {
    if (busy || query.isEmpty) {
      return;
    }
    _foundCount = 0;
    _searched = true;
    _stopped = false;

    final address = SearchAddress(where: where, query: query, limits: _limits);
    _address = address;

    // Вкладка со своим источником: находки складываются прямо в него, и
    // «передать список панели» становится нечем и некуда — панель получает ту
    // же вкладку.
    //
    // **Не показывая**: панель человек не отдавал. Вкладка видна в ряду, к ней
    // можно перейти — а подменять содержимое панели за спиной незачем
    // (`docs/spec/file-search.md`, §4.3).
    final tab = await app.openPanel(_side, like: panel, show: false);
    _tab = tab;
    await tab.session.openPath(address.toString());

    final run = app.runOperation(runId: runId, onFound: _grew);
    _run = run;
    // Работа заводится в общем реестре — том же, где копирование. С этого
    // момента её можно отправить в фон и вернуть щелчком по полоске, а
    // «чем вернуть» реестр держит здесь же.
    app.operations.register(
      OperationRun(
        runId: runId,
        operation: run,
        title: app.strings.tr('Find {what}', args: {'what': address.what}),
        bringToFront: () => showResults?.call(),
      ),
    );
    notifyListeners();

    run.status.addListener(() {
      _at = run.status.message;
      _redraw();
    });

    try {
      run.start(SearchWork.specFor(address));
      await run.result;
    } on OperationCanceled {
      // Прекратили — найденное остаётся: половина ответа лучше, чем ничего.
    } on Object {
      // Дерево могло уехать из-под ног. Показывать нечего: что нашлось, то и
      // осталось.
    } finally {
      _run = null;
      _at = '';
      // Работа кончилась — итог показывается сразу, не дожидаясь окна
      // ограничителя. Заодно отложенное уведомление не переживёт окна: висящий
      // таймер роняет виджет-тест, и правильно делает.
      _redraw.flush();
    }
  }

  /// С какой стороны показывать вкладку — с той, где стоит панель, из которой
  /// искали.
  ViewportPosition get _side =>
      identical(app.panelAt(ViewportPosition.right).session, panel) ? ViewportPosition.right : ViewportPosition.left;

  void _grew(List<FileEntry> entries) {
    _foundCount += entries.length;
    _redraw();
  }

  /// Обход прекратили руками: итог говорит об этом словом, а не молчанием.
  bool get stopped => _stopped;
  bool _stopped = false;

  /// Прекратить обход. То, что уже нашлось, остаётся.
  ///
  /// Молча (`cancel`), а не с вопросом: кнопку «Стоп» и нажали затем, чтобы
  /// прекратить, — переспрашивать после неё значит спрашивать дважды.
  void stop() {
    if (busy) {
      _stopped = true;
    }
    _run?.cancel();
  }

  /// Отдать находки панели — и уйти из окна.
  ///
  /// Отдавать, по существу, нечего: вкладка с находками уже живёт, и панель
  /// её уже показывает. Остаётся показать её наверняка (человек мог за это
  /// время переключить вкладку) и убрать окно.
  ///
  /// Незаконченный поиск при этом продолжается — в фоне и на виду: полоска
  /// показывает, что он идёт, а список растёт сам, потому что растёт его
  /// источник.
  Future<void> toPanel() async {
    final tab = _tab;
    if (tab == null) {
      return;
    }
    if (busy) {
      toBackground();
    } else {
      app.operations.forget(runId);
      close?.call();
    }
    app.showPanel(_side, tab);
    app.activate(tab.session);
  }

  /// Перейти к найденному: панель открывает его каталог, курсор встаёт на нём.
  ///
  /// Не открыть сам файл: в списке находок чаще нужно первое, а открыть его
  /// оттуда можно `F3`.
  ///
  /// Поиск при этом **уходит в фон, а не пропадает**: сходить к одной находке —
  /// не повод потерять остальные.
  Future<void> goTo() async {
    final entry = current;
    if (!canGoTo || entry == null) {
      return;
    }
    toBackground();
    // В **свою** панель, а не во вкладку поиска: её человек не открывал, и
    // показывать ему находку в невидимом наборе значило бы не показать ничего
    // (`docs/spec/file-search.md`, §4.3).
    app.activate(panel);
    await panel.openPath(entry.directoryPath);
    panel.setCursorToName(entry.name);
  }

  /// `F3` и `F4` над находкой: встать на неё и открыть.
  ///
  /// Открывают не здесь: [goTo] ставит курсор панели, а дальше делает своё дело
  /// обычная команда — `file.view` или `file.edit`. Они берут узел из-под
  /// курсора, и второго пути открытия файла в приложении заводить не надо.
  Future<void> open(String commandId) async {
    if (!canGoTo) {
      return;
    }
    await goTo();
    app.commands.run(commandId);
  }
}
