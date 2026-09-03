import 'package:flutter/foundation.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import '../core/panel_session.dart';
import '../link/link.dart';
import '../ui/remote_content.dart';

export 'package:fc_ui_api/fc_ui_api.dart' show Panel;

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
  PanelController(this.id, this.session, {Link? link}) : _link = link {
    // Список и размеры на этой стороне не пересылаются: узлы те же самые, и
    // перерисовки хватает.
    _unwatch = session.watch(onChanged: notifyListeners, onListed: notifyListeners, onSized: (_) => notifyListeners());
  }

  late final VoidCallback _unwatch;

  @override
  final PanelId id;

  /// Панель со стороны ядра — всё, что она на самом деле делает.
  final PanelSession session;

  /// Дверь к ядру: через неё едут байты содержимого.
  final Link? _link;

  @override
  Content contentOf(FileEntry entry) {
    final door = _link;
    final ref = _refTo(entry);
    if (door == null || ref == null) {
      return const NoContent();
    }
    return RemoteContent(door, ref, length: entry.size);
  }

  // --- источник ---

  @override
  SourceInfo get source => session.sourceInfo;

  // --- каталог ---

  @override
  String get path => session.path;

  @override
  String get directoryName => session.directoryName;

  @override
  String get shellDirectory => session.shellDirectory;

  @override
  Future<bool> showFound(String runId, {String title = ''}) async {
    final door = _link;
    if (door == null) {
      return false;
    }
    final reply = await door.call(ShowFound(id, runId, title: title));
    return reply is CoreOpened && reply.opened;
  }

  @override
  Future<List<FileEntry>> namesIn(String path) async {
    final door = _link;
    if (door == null) {
      return const [];
    }
    final reply = await door.call(ListNames(id, path));
    return reply is CoreEntries ? reply.entries : const [];
  }

  @override
  bool get canGoUp => session.canGoUp;

  @override
  List<FileEntry> get entries => session.entries;

  @override
  PanelPhase get phase => session.status;

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
  Future<bool> openPath(String path, {bool allowConnect = true}) => session.openPath(path, allowConnect: allowConnect);

  @override
  Future<bool> canWriteTo(FileEntry entry) async {
    final door = _link;
    final ref = _refTo(entry);
    if (door == null || ref == null) {
      return false;
    }
    final reply = await door.call(CheckWriteAccess(ref));
    return reply is CoreFlag && reply.value;
  }

  /// Ссылка на строку: место в списке и его номер.
  EntryRef? _refTo(FileEntry entry) {
    final index = session.entries.indexWhere((candidate) => candidate.name == entry.name);
    return index < 0 ? null : EntryRef.inPanel(id, index, session.generation);
  }

  @override
  Future<FileEntry?> enter(FileEntry entry) async {
    final index = session.entries.indexWhere((candidate) => candidate.name == entry.name);
    if (index < 0) {
      return null;
    }
    session.setCursorIndex(index);
    return enterCurrent();
  }

  @override
  Future<FileEntry?> enterCurrent() async {
    final blocked = await session.enterCurrent();
    return blocked == null ? null : session.entryOf(blocked);
  }

  @override
  Future<void> goUp() => session.goUp();

  @override
  Future<void> reload() => session.reload();

  @override
  void cancel() => session.cancel();

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
  FileEntry? get currentEntry {
    final node = session.currentNode;
    return node == null ? null : session.entryOf(node);
  }

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
  Set<String> get marked => session.selection.names;

  @override
  bool isMarked(FileEntry entry) => session.selection.names.contains(entry.name);

  @override
  void setMarks(Set<String> names) => session.setMarks(names);

  @override
  void mark(FileEntry entry) => setMarks({...marked, entry.name});

  @override
  void unmark(FileEntry entry) => setMarks({...marked}..remove(entry.name));

  @override
  void markAll() => session.markAll();

  @override
  void clearMarks() => setMarks(const {});

  @override
  List<FileEntry> get targets {
    if (marked.isEmpty) {
      final current = currentEntry;
      return current == null || current.isParent ? const [] : [current];
    }
    final names = marked;
    return [
      for (final entry in entries)
        if (names.contains(entry.name)) entry,
    ];
  }

  @override
  int get markedSize => session.selectionSize;

  @override
  bool get markedSizeIsFinal => session.selectionSizeIsFinal;

  @override
  void toggleCurrentMark() => session.toggleCurrentMark();

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

  @override
  Future<R> runWork<R>(Future<R> Function(TaskOperation<void, R> op) body, {String status = 'Loading…'}) =>
      session.runWork(body, status: status);

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
    _unwatch();
    session.dispose();
    super.dispose();
  }
}

/// Содержимого нет вовсе: приложение собрано без ядра или строка уже не та.
class NoContent implements Content {
  const NoContent();

  @override
  int get length => FileEntry.unknownSize;

  @override
  Stream<List<int>> read({int offset = 0}) => const Stream.empty();
}
