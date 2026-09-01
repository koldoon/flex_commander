import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

import 'search_query.dart';
import 'search_results_provider.dart';
import 'search_run.dart';

/// Строка списка находок: заголовок каталога или сама находка под ним.
///
/// **Плоско, а не деревом.** Список обязан быть ленивым — находок бывают
/// тысячи, — а ленивый строит только видимое лишь тогда, когда все строки одной
/// высоты и он знает, сколько их. Дерево ни того, ни другого не даёт
/// (`spec/file-search.md`, §3.2).
class FoundRow {
  const FoundRow.header(this.path) : node = null, index = -1;
  const FoundRow.item(FsNode this.node, this.index) : path = '';

  /// Путь каталога — у заголовка; у находки пусто.
  final String path;

  /// Сама находка; null — это заголовок.
  final FsNode? node;

  /// Номер находки в [FindFilesState.found]; -1 у заголовка.
  final int index;

  bool get isHeader => node == null;
}

/// Состояние окна поиска: о чём спросили, что нашлось и идёт ли обход.
class FindFilesState extends ChangeNotifier {
  FindFilesState({required this.app, required this.panel, required this.where, required this.runId});

  final Application app;

  /// Имя этой работы в реестре: у каждого поиска своё, их может идти сколько
  /// угодно — ровно как копирований.
  final String runId;

  /// Панель, в каталоге которой ищут и в которую отдают найденное.
  final Panel panel;

  /// Где искать. Не поле окна: чтобы искать в другом месте, туда переходят
  /// панелью — так не бывает поиска «не там, где думает человек».
  final DirectoryNode where;

  SearchQuery query = const SearchQuery(mask: '');

  /// Найденное — в том порядке, в каком находилось.
  final List<FsNode> found = [];

  /// Строки списка: заголовки каталогов и находки под ними.
  ///
  /// Собираются **по ходу обхода**, за одно действие на находку, — а не
  /// пересобираются на каждую перерисовку. Именно на пересборке приложение и
  /// вставало.
  final List<FoundRow> rows = [];

  /// Номер строки для каждой находки. Нужен только затем, чтобы подвести
  /// выбранную под обзор: курсор ходит по находкам, а прокрутка — по строкам.
  final List<int> _rowOfFound = [];

  /// Каталог последней находки: с ним сличается следующая, и по несовпадению
  /// добавляется заголовок. Одно сравнение вместо группировки.
  String? _lastDirectory;

  /// Какой строкой показана эта находка.
  int rowOfFound(int index) => index >= 0 && index < _rowOfFound.length ? _rowOfFound[index] : -1;

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
  Operation<SearchQuery, List<FsNode>>? _run;

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

  /// Строка находок под курсором; -1 — не выбрана ни одна.
  int get selected => _selected;
  int _selected = -1;

  /// Есть куда перейти: строка выбрана и у неё есть каталог.
  bool get canGoTo => _selected >= 0 && _selected < found.length && found[_selected].parentDirectory != null;

  /// Есть что искать: маска непустая и обход не идёт.
  bool get canStart => !busy && !query.isEmpty;

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

  /// `Close`: окно и работа уходят вместе.
  void finish() {
    stop();
    app.operations.forget(runId);
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

  void select(int index) {
    if (index == _selected) {
      return;
    }
    _selected = index;
    notifyListeners();
  }

  void typed(String mask) {
    query = query.copyWith(mask: mask);
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

  /// Начать обход. Идёт он фоном: окно остаётся на месте и пополняется.
  Future<void> start() async {
    if (busy || query.isEmpty) {
      return;
    }
    found.clear();
    rows.clear();
    _rowOfFound.clear();
    _lastDirectory = null;
    _selected = -1;
    _searched = true;
    _stopped = false;
    final run = SearchRun.from(where, onFound: _add);
    _run = run;
    // Работа заводится в общем реестре — том же, где копирование. С этого
    // момента её можно отправить в фон и вернуть щелчком по полоске, а
    // «чем вернуть» реестр держит здесь же.
    app.operations.register(
      OperationRun(
        runId: runId,
        operation: run,
        title: 'Find "${query.mask}"',
        bringToFront: () => showResults?.call(),
      ),
    );
    notifyListeners();

    run.status.addListener(() {
      _at = run.status.message;
      _redraw();
    });

    try {
      run.start(query);
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

  /// Отдать найденное панели — и уйти совсем.
  ///
  /// Работа при этом забывается: находки уже у человека, и держать их второй
  /// раз полоской незачем.
  Future<void> toPanel() async {
    if (found.isEmpty) {
      return;
    }
    finish();
    // Каталог поиска — родитель списка: `..` из находок возвращает туда, где
    // панель стояла, и никакого «запомненного места» для этого не нужно.
    final results = SearchResultsProvider(title: query.mask, found: List.of(found), parent: where);
    await panel.open(results.rootDirectory);
  }

  /// Перейти к найденному: панель открывает его каталог, курсор встаёт на нём.
  ///
  /// Не открыть сам файл: в списке находок чаще нужно первое, а открыть его
  /// оттуда можно `F3`.
  ///
  /// Поиск при этом **уходит в фон, а не пропадает**: сходить к одной находке —
  /// не повод потерять остальные. Полоска остаётся, и щелчок по ней возвращает
  /// тот же список.
  Future<void> goTo() async {
    if (!canGoTo) {
      return;
    }
    final node = found[_selected];
    toBackground();
    await panel.open(node.parentDirectory!);
    panel.setCursorToName(node.name);
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

  void _add(FsNode node) {
    // Каталог называется один раз на пачку — как в `mc`: обход идёт каталогами,
    // и находки из одного приходят подряд.
    final directory = node.parentDirectory?.displayPath ?? '';
    if (directory != _lastDirectory) {
      _lastDirectory = directory;
      rows.add(FoundRow.header(directory));
    }
    found.add(node);
    _rowOfFound.add(rows.length);
    rows.add(FoundRow.item(node, found.length - 1));
    _redraw();
  }
}
