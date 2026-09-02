import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import '../core/panel_session.dart';

export 'package:fc_ui_api/fc_ui_api.dart' show Panel, PanelStatus;

/// Панель со стороны экрана — [Panel] поверх сеанса ядра.
///
/// **Временная сборка**, и об этом стоит сказать прямо. Сеанс
/// ([PanelSession]) — это уже ядро: он читает каталоги, монтирует архивы и
/// считает размеры, ничего не зная об экране. Здесь же — переходник, который
/// отдаёт его наружу тем самым интерфейсом, к которому написаны все команды и
/// виджеты, и переводит «что-то изменилось» в перерисовку.
///
/// Живого при этом ходит слишком много: узлы, провайдер, живая пометка. Уйдёт
/// это на Э3, когда на место переходника встанет зеркало поверх линка, а панель
/// начнёт получать значения (`docs/spec/client-server.md`, §7). Пока стороны в
/// одном изоляте, и переходник честнее, чем вторая копия той же тысячи строк.
class PanelController extends ChangeNotifier implements Panel {
  PanelController(this.session) {
    session.onChanged = notifyListeners;
    // Список и размеры на этой стороне не пересылаются: узлы те же самые, и
    // перерисовки хватает.
    session.onListed = notifyListeners;
    session.onSized = (_) => notifyListeners();
  }

  /// Панель со стороны ядра — всё, что она на самом деле делает.
  final PanelSession session;

  // --- источник ---

  @override
  TreeProvider get provider => session.provider;

  @override
  TreeEditor? get editor => session.editor;

  @override
  String get contentKind => session.contentKind;

  // --- каталог ---

  @override
  DirectoryNode? get directory => session.directory;

  @override
  List<FsNode> get nodes => session.nodes;

  @override
  PanelStatus get status => switch (session.status) {
    PanelPhase.idle => PanelStatus.idle,
    PanelPhase.loading => PanelStatus.loading,
    PanelPhase.error => PanelStatus.error,
  };

  @override
  FsError? get error => session.error;

  @override
  bool get busy => session.busy;

  @override
  String? get statusText => session.statusText;

  @override
  void setStatusText(String? text) => session.setStatusText(text);

  @override
  String? get headerText => session.headerText;

  @override
  void setHeaderText(String? text) => session.setHeaderText(text);

  @override
  Future<void> open(DirectoryNode dir) => session.open(dir);

  @override
  Future<bool> openPath(String path, {bool allowConnect = true}) => session.openPath(path, allowConnect: allowConnect);

  @override
  ProviderLease? leaseProvider() => session.leaseProvider();

  @override
  Operation<String, ResolvedNode> resolvePath() => session.resolvePath();

  @override
  Future<FsNode?> enterCurrent() => session.enterCurrent();

  @override
  Future<void> goUp() => session.goUp();

  @override
  Future<void> reload() => session.reload();

  @override
  void cancel() => session.cancel();

  @override
  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String status = 'Loading…'}) =>
      session.runWork(body, status: status);

  // --- курсор ---

  /// Сколько строк помещается в видимой части списка.
  ///
  /// Остаётся здесь и на ту сторону не поедет: шаг страницей — это про показ,
  /// и считать его будет тот, у кого список на руках.
  @override
  int pageSize = 20;

  @override
  int get cursorIndex => session.cursorIndex;

  @override
  FsNode? get currentNode => session.currentNode;

  @override
  void moveCursor(int delta) => session.setCursorIndex(session.cursorIndex + delta);

  @override
  void moveCursorPage(int direction) => moveCursor(direction * (pageSize - 1).clamp(1, pageSize));

  @override
  void setCursorIndex(int index) => session.setCursorIndex(index);

  @override
  void setCursorToFirst() => session.setCursorIndex(0);

  @override
  void setCursorToLast() => session.setCursorIndex(session.nodes.length - 1);

  @override
  void setCursorToName(String name) => session.setCursorToName(name);

  // --- пометка ---

  @override
  PanelSelection get selection => session.selection;

  @override
  int get selectionSize => session.selectionSize;

  @override
  bool get selectionSizeIsFinal => session.selectionSizeIsFinal;

  @override
  void toggleCurrentMark() => session.toggleCurrentMark();

  @override
  void markAll() => session.markAll();

  @override
  void measureDirectories() => session.measureDirectories();

  // --- вид ---

  @override
  ColumnLayout get columns => session.columns;

  @override
  void setColumnLayout(ColumnLayout layout) => session.setColumnLayout(layout);

  @override
  SortSpec get sort => session.sort;

  @override
  void sortBy(FsColumn column) => session.sortBy(column);

  @override
  bool get showHidden => session.showHidden;

  @override
  Future<void> setShowHidden(bool value) => session.setShowHidden(value);

  @override
  PanelSettings get settings => session.settings;

  // --- область ---

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

  @override
  void close() => session.close();

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }
}
