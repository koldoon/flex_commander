import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import '../values/fs_error.dart';
import 'file_entry.dart';
import 'source_info.dart';

/// Чем панель занята сейчас.
enum PanelPhase { idle, loading, error }

/// Состояние панели — всё, кроме самого списка.
///
/// Список едет отдельно ([PanelListing]): он большой и меняется реже всего
/// прочего, а курсор ходит по нему десятки раз в секунду. Вместе они и есть то,
/// что зеркалит интерфейс (`docs/spec/client-server.md`, §4.5).
class PanelState {
  const PanelState({
    required this.source,
    this.path = '',
    this.phase = PanelPhase.idle,
    this.error,
    this.busy = false,
    this.statusText,
    this.headerText,
    this.cursorIndex = 0,
    this.cursorSeq = 0,
    this.generation = 0,
    this.sort = const SortSpec(),
    required this.columns,
    this.showHidden = false,
    this.marked = const {},
    this.markedSize = 0,
    this.markedSizeIsFinal = true,
  });

  /// Откуда панель берёт содержимое сейчас.
  final SourceInfo source;

  /// Путь показанного каталога — он же заголовок панели по умолчанию.
  final String path;

  final PanelPhase phase;
  final FsError? error;

  /// Идёт длительная работа: клавиатура панели больше не принадлежит.
  final bool busy;

  /// Строка состояния панели: «Loading…», «Opening a.zip…», текст ошибки — и
  /// то, что выставила команда.
  ///
  /// Одна на всех, как и было: пишут в неё и ядро, и команды, и выигрывает
  /// последний сказавший. Разделить её на «ход дела» и «слово команды» стоит
  /// того лишь тогда, когда обход границы на каждую букву быстрого поиска
  /// станет заметен, — а до тех пор второе поле было бы усложнением без
  /// причины.
  final String? statusText;

  /// Заголовок, выставленный командой; null — показывается путь каталога.
  ///
  /// Нужен тому, кто заполняет панель не каталогом: находкам, ветке
  /// соединения, списку закладок.
  final String? headerText;

  final int cursorIndex;

  /// Номер заявки, на которую этот курсор — ответ.
  ///
  /// Зеркало двигает курсор у себя сразу и запоминает номер своей просьбы.
  /// Подтверждение с меньшим номером — опоздавшее, и слушать его нельзя:
  /// при удержании стрелки курсор дёргался бы назад.
  final int cursorSeq;

  /// Номер списка: растёт с каждым новым. По нему ядро отвергает заявки на
  /// строки того списка, которого уже нет.
  final int generation;

  final SortSpec sort;
  final ColumnLayout columns;
  final bool showHidden;

  /// Помеченное — именами: список приезжает отдельно, и связывать пометку с
  /// его порядком нельзя, иначе перечитывание каталога сдвинуло бы её.
  final Set<String> marked;

  /// Суммарный размер помеченного. Растёт по ходу обхода каталогов.
  final int markedSize;
  final bool markedSizeIsFinal;

  PanelState copyWith({
    SourceInfo? source,
    String? path,
    PanelPhase? phase,
    FsError? error,
    bool clearError = false,
    bool? busy,
    String? statusText,
    bool clearStatus = false,
    String? headerText,
    bool clearHeader = false,
    int? cursorIndex,
    int? cursorSeq,
    int? generation,
    SortSpec? sort,
    ColumnLayout? columns,
    bool? showHidden,
    Set<String>? marked,
    int? markedSize,
    bool? markedSizeIsFinal,
  }) => PanelState(
    source: source ?? this.source,
    path: path ?? this.path,
    phase: phase ?? this.phase,
    error: clearError ? null : (error ?? this.error),
    busy: busy ?? this.busy,
    statusText: clearStatus ? null : (statusText ?? this.statusText),
    headerText: clearHeader ? null : (headerText ?? this.headerText),
    cursorIndex: cursorIndex ?? this.cursorIndex,
    cursorSeq: cursorSeq ?? this.cursorSeq,
    generation: generation ?? this.generation,
    sort: sort ?? this.sort,
    columns: columns ?? this.columns,
    showHidden: showHidden ?? this.showHidden,
    marked: marked ?? this.marked,
    markedSize: markedSize ?? this.markedSize,
    markedSizeIsFinal: markedSizeIsFinal ?? this.markedSizeIsFinal,
  );

  @override
  String toString() => 'PanelState($path, ${phase.name}, cursor $cursorIndex)';
}

/// Список панели целиком.
///
/// Отдельно от состояния и с номером: пока сообщение шло, панель могли увести
/// в другой каталог, и по номеру видно, чей это список.
class PanelListing {
  const PanelListing({required this.generation, required this.entries});

  final int generation;
  final List<FileEntry> entries;

  @override
  String toString() => 'PanelListing(#$generation, ${entries.length})';
}
