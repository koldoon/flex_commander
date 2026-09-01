import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';

import 'search_query.dart';
import 'search_results_provider.dart';
import 'search_run.dart';

/// Состояние окна поиска: о чём спросили, что нашлось и идёт ли обход.
class FindFilesState extends ChangeNotifier {
  FindFilesState({required this.panel, required this.where});

  /// Панель, в каталоге которой ищут и в которую отдают найденное.
  final Panel panel;

  /// Где искать. Не поле окна: чтобы искать в другом месте, туда переходят
  /// панелью — так не бывает поиска «не там, где думает человек».
  final DirectoryNode where;

  SearchQuery query = const SearchQuery(mask: '');

  /// Найденное — в том порядке, в каком находилось.
  final List<FsNode> found = [];

  /// Где обход сейчас; пусто — не идёт.
  String get at => _at;
  String _at = '';

  bool get busy => _run != null;
  Operation<SearchQuery, List<FsNode>>? _run;

  /// Искали хоть раз: до первого поиска «ничего не нашлось» — не ответ, а
  /// молчание.
  bool get searched => _searched;
  bool _searched = false;

  /// Закрыть окно; ставит тот, кто его показал.
  VoidCallback? close;

  /// Строка находок под курсором; -1 — не выбрана ни одна.
  int get selected => _selected;
  int _selected = -1;

  /// Есть куда перейти: строка выбрана и у неё есть каталог.
  bool get canGoTo => _selected >= 0 && _selected < found.length && found[_selected].parentDirectory != null;

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
    _selected = -1;
    _searched = true;
    final run = SearchRun.from(where, onFound: _add);
    _run = run;
    notifyListeners();

    run.status.addListener(() {
      _at = run.status.message;
      notifyListeners();
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
      notifyListeners();
    }
  }

  /// Прекратить обход. То, что уже нашлось, остаётся.
  ///
  /// Молча (`cancel`), а не с вопросом: кнопку «Стоп» и нажали затем, чтобы
  /// прекратить, — переспрашивать после неё значит спрашивать дважды.
  void stop() => _run?.cancel();

  /// Отдать найденное панели — и уйти с глаз.
  Future<void> toPanel() async {
    if (found.isEmpty) {
      return;
    }
    stop();
    // Каталог поиска — родитель списка: `..` из находок возвращает туда, где
    // панель стояла, и никакого «запомненного места» для этого не нужно.
    final results = SearchResultsProvider(title: query.mask, found: List.of(found), parent: where);
    close?.call();
    await panel.open(results.rootDirectory);
  }

  /// Перейти к найденному: панель открывает его каталог, курсор встаёт на нём.
  ///
  /// Не открыть сам файл: в списке находок чаще нужно первое, а открыть его
  /// оттуда можно и `F3`.
  Future<void> goTo() async {
    if (!canGoTo) {
      return;
    }
    final node = found[_selected];
    stop();
    close?.call();
    await panel.open(node.parentDirectory!);
    panel.setCursorToName(node.name);
  }

  /// Откуда находка — путь её каталога, укороченный до места поиска.
  ///
  /// В плоском списке одни имена бесполезны: `main.dart` там будет десяток.
  String whereOf(FsNode node) {
    final directory = node.parentDirectory?.pathString ?? '';
    final root = where.pathString;
    if (directory == root) {
      return '.';
    }
    return directory.startsWith(root) ? directory.substring(root.length).replaceFirst(RegExp(r'^/+'), '') : directory;
  }

  void _add(FsNode node) {
    found.add(node);
    notifyListeners();
  }
}
