import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import '../settings/app_settings.dart';
import '../tree/fs_node.dart';
import '../tree/tree_provider.dart';
import 'panel_selection.dart';

enum PanelStatus { idle, loading, error }

/// Панель файлового менеджера — то, чем оперируют команды.
///
/// Аналог `IPanel` референса: описывает, что панель умеет, но не то, как она
/// это делает и как себя рисует. Команды пишутся против этого интерфейса,
/// поэтому их не придётся трогать ни при смене реализации панели, ни при
/// появлении второй разновидности панели (дерево каталогов, результаты поиска).
abstract interface class Panel {
  /// Откуда панель берёт содержимое.
  TreeProvider get provider;

  /// Редактор дерева, если провайдер умеет изменять содержимое; иначе null —
  /// например, у архива, открытого только на просмотр. С него начинается
  /// любая файловая операция.
  ///
  /// Это движок переноса, а не сам провайдер: обход, конфликты и прогресс —
  /// общие для всех источников, провайдер даёт только примитивы ([NodeEditor]).
  /// Поэтому приёмник может оказаться из другого провайдера, и команду это
  /// не касается.
  TreeEditor? get editor;

  // --- каталог ---

  DirectoryNode? get directory;

  /// Отсортированное содержимое каталога.
  List<FsNode> get nodes;

  PanelStatus get status;

  FsError? get error;

  /// Идёт длительная операция.
  bool get busy;

  /// Панель активна: в ней курсор и ввод с клавиатуры.
  bool get active;

  /// Текст, выставленный командой; null — панель показывает объект под курсором.
  String? get statusText;

  void setStatusText(String? text);

  /// Открыть каталог. Отменяет незавершённое чтение этой же панели.
  Future<void> open(DirectoryNode dir);

  /// Открыть каталог по строке пути. false — путь недоступен или это не каталог.
  Future<bool> openPath(String path);

  /// Войти в объект под курсором. Возвращает узел, в который войти нельзя
  /// (обычный файл); null, если переход выполнен.
  Future<FsNode?> enterCurrent();

  /// На уровень вверх; курсор встаёт на объект, через который вошли.
  Future<void> goUp();

  /// Перечитать текущий каталог, сохранив курсор и пометку.
  Future<void> reload();

  /// Прервать текущую операцию.
  void cancel();

  // --- курсор ---

  int get cursorIndex;

  FsNode? get currentNode;

  /// Сколько строк помещается в видимой части списка; от этого считается шаг
  /// PgUp/PgDn. Значение выставляет таблица.
  int get pageSize;

  set pageSize(int value);

  void moveCursor(int delta);

  void moveCursorPage(int direction);

  void setCursorIndex(int index);

  void setCursorToFirst();

  void setCursorToLast();

  void setCursorToName(String name);

  // --- пометка ---

  PanelSelection get selection;

  /// Суммарный размер помеченных объектов вместе с содержимым каталогов.
  ///
  /// Размер файлов известен сразу, каталоги обходятся фоном, поэтому значение
  /// растёт по ходу подсчёта.
  int get selectionSize;

  /// Подсчёт [selectionSize] закончен.
  bool get selectionSizeIsFinal;

  /// Инвертировать пометку объекта под курсором и сдвинуть курсор вниз.
  void toggleCurrentMark();

  void markAll();

  // --- вид ---

  ColumnLayout get columns;

  void setColumnLayout(ColumnLayout layout);

  SortSpec get sort;

  /// Сортировка по колонке: та же колонка меняет направление.
  void sortBy(FsColumn column);

  bool get showHidden;

  Future<void> setShowHidden(bool value);

  /// Текущее состояние панели в виде сохраняемых настроек.
  PanelSettings get settings;
}
