import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import '../async/progress_report.dart';
import '../values/fs_error.dart';
import 'entry_ref.dart';
import 'file_entry.dart';
import 'operation_spec.dart';
import 'panel_state.dart';

/// О чём интерфейс просит ядро.
///
/// Просьб немного, и это мера здоровья границы: полтора десятка покрывают весь
/// стейт приложения. Пошёл счёт к тридцати — граница снова не там, и это повод
/// остановиться, а не дописать ещё одну (`docs/spec/client-server.md`, §5).
///
/// Всё, что здесь лежит, — данные: строки, числа, флаги и значения границы.
/// Живого не ходит ничего.
sealed class CoreRequest {
  const CoreRequest();
}

/// Первое слово: что у ядра есть прямо сейчас.
///
/// До ответа дверь закрыта — панель, попросившая каталог раньше, ждёт его, а не
/// получает отказ.
final class Handshake extends CoreRequest {
  const Handshake();
}

/// Открыть каталог по строке пути.
///
/// [allowConnect] — можно ли ради этого подключаться к источнику по адресу.
/// false нужен восстановлению при запуске: сохранённый адрес означал бы поход
/// в сеть на каждом запуске.
final class OpenPath extends CoreRequest {
  const OpenPath(this.panel, this.path, {this.allowConnect = true});

  final PanelId panel;
  final String path;
  final bool allowConnect;
}

/// Войти в объект: каталог, архив, ссылка на каталог.
///
/// Ответом приходит то, во что войти нельзя (обычный файл), — им займётся
/// команда; null означает, что переход выполнен.
final class OpenEntry extends CoreRequest {
  const OpenEntry(this.panel, this.entry);

  final PanelId panel;
  final EntryRef entry;
}

/// На уровень вверх; курсор встаёт на объект, через который вошли.
final class GoUp extends CoreRequest {
  const GoUp(this.panel);

  final PanelId panel;
}

/// Перечитать каталог, сохранив курсор и пометку.
final class Reload extends CoreRequest {
  const Reload(this.panel);

  final PanelId panel;
}

/// Поставить курсор на строку.
///
/// Куда именно, считает интерфейс: список у него на руках, и шаг страницей,
/// переход к имени и упор в края — это про показ. Через границу едет уже
/// результат, а [seq] позволяет зеркалу отличить свежий ответ от опоздавшего
/// (`docs/spec/client-server.md`, §5.5).
final class MoveCursor extends CoreRequest {
  const MoveCursor(this.panel, this.index, this.seq);

  final PanelId panel;
  final int index;
  final int seq;
}

/// Заменить пометку целиком — именами.
///
/// Одна просьба на все способы пометить: по маске, всё, снять. Развернуть маску
/// в имена может и интерфейс — список у него есть.
final class SetMarks extends CoreRequest {
  const SetMarks(this.panel, this.names);

  final PanelId panel;
  final Set<String> names;
}

/// Пометить объект под курсором и сдвинуть курсор вниз.
///
/// Отдельно от [SetMarks], потому что это одно действие: клавиша `Space`
/// помечает и переходит к следующему, а курсор — ядровый.
final class ToggleMark extends CoreRequest {
  const ToggleMark(this.panel);

  final PanelId panel;
}

/// Как показывать список: сортировка, колонки, скрытые.
final class Arrange extends CoreRequest {
  const Arrange(this.panel, {this.sort, this.columns, this.showHidden});

  final PanelId panel;
  final SortSpec? sort;
  final ColumnLayout? columns;
  final bool? showHidden;
}

/// Посчитать размеры всех каталогов текущего каталога.
final class MeasureDirectories extends CoreRequest {
  const MeasureDirectories(this.panel);

  final PanelId panel;
}

/// Строка состояния панели, выставленная командой.
///
/// Строка одна на всех — пишут в неё и ядро, и команды, — поэтому и живёт она
/// там же, где остальное состояние. Уходит просьба не дожидаясь ответа, а
/// зеркало пишет к себе сразу: текст должен появиться в тот же кадр, в котором
/// команда его выставила.
final class SetStatusText extends CoreRequest {
  const SetStatusText(this.panel, this.text);

  final PanelId panel;
  final String? text;
}

/// Заголовок панели, выставленный командой; null — показывается путь.
final class SetHeaderText extends CoreRequest {
  const SetHeaderText(this.panel, this.text);

  final PanelId panel;
  final String? text;
}

/// Завести работу и запустить её.
///
/// Ответом приходит её имя ([CoreRunning]); дальше о ней рассказывают события,
/// а говорят с ней [TellOperation].
final class RunOperation extends CoreRequest {
  const RunOperation(this.runId, this.spec);

  /// Имя работы даёт **эта** сторона, а не ядро.
  ///
  /// Иначе между просьбой и ответом с именем есть промежуток, в котором работа
  /// уже идёт, уже рассказывает о себе — а слушателю нечем узнать, что это она.
  /// С именем на руках подписка встаёт до запуска.
  final String runId;
  final OperationSpec spec;
}

/// Дадут ли записать в этот файл.
///
/// Спрашивают **до** работы: узнать об отказе после часа правки значит остаться
/// с текстом, который некуда деть. Ответ — да или нет, и ходить за ним больше
/// некуда: права знает только та сторона.
final class CheckWriteAccess extends CoreRequest {
  const CheckWriteAccess(this.entry);

  final EntryRef entry;
}

/// Открыть содержимое файла и читать его потоком.
///
/// Разговор, а не ответ: файл бывает больше памяти, и показывать ход дела
/// нужно по ходу, а не в конце. Куски едут событиями, конец — тоже.
final class ReadContent extends CoreRequest {
  const ReadContent(this.runId, this.entry, {this.offset = 0});

  /// Имя разговора даёт эта сторона — как и у работ: подписка встаёт раньше,
  /// чем поедет первый кусок.
  final String runId;
  final EntryRef entry;

  /// Сколько байт пропустить от начала.
  final int offset;
}

/// Сказать в идущую работу: отмена, ответ на вопрос.
final class TellOperation extends CoreRequest {
  const TellOperation(this.runId, this.input);

  final String runId;
  final OperationInput input;
}

/// Прервать то, чем панель занята.
final class CancelWork extends CoreRequest {
  const CancelWork(this.panel);

  final PanelId panel;
}

/// Что ядро отвечает на просьбу.
sealed class CoreReply {
  const CoreReply();
}

/// Сделано; сказать больше нечего.
final class CoreDone extends CoreReply {
  const CoreDone();
}

/// Не вышло — и вот почему. Причина нужна тому, кто просил: «нет такого пути»
/// и «такой протокол мы не умеем» — разные ответы.
final class CoreFailed extends CoreReply {
  const CoreFailed(this.error);

  final FsError error;
}

/// Открылось или нет.
final class CoreOpened extends CoreReply {
  const CoreOpened(this.opened);

  final bool opened;
}

/// Вошли (null) или войти нельзя — вот во что.
final class CoreEntered extends CoreReply {
  const CoreEntered(this.entry);

  final FileEntry? entry;
}

/// Да или нет.
final class CoreFlag extends CoreReply {
  const CoreFlag(this.value);

  final bool value;
}

/// Ответ на рукопожатие: что у ядра есть прямо сейчас.
///
/// Панели и их списки — и ничего больше. Схемы архивов и адресов сюда не
/// поехали нарочно: решает, что делать с файлом, на котором нажали `Enter`,
/// **ядро**, и знать это интерфейсу незачем. Понадобится — приедет; заранее
/// возить то, чего никто не спрашивает, значит городить язык впрок.
final class CoreReady extends CoreReply {
  const CoreReady({required this.states, required this.listings});

  /// Состояние каждой панели.
  final Map<PanelId, PanelState> states;

  /// И её список.
  final Map<PanelId, PanelListing> listings;
}

/// О чём ядро рассказывает само.
sealed class CoreEvent {
  const CoreEvent();
}

/// Состояние панели изменилось — целиком.
///
/// Целиком, а не полем: без списка это десяток чисел и флагов, и городить ради
/// них язык заплаток дороже, чем везти всё. Список едет отдельно
/// ([PanelListed]) и только когда он и вправду сменился.
final class PanelChanged extends CoreEvent {
  const PanelChanged(this.panel, this.state);

  final PanelId panel;
  final PanelState state;
}

/// У панели новый список.
final class PanelListed extends CoreEvent {
  const PanelListed(this.panel, this.listing);

  final PanelId panel;
  final PanelListing listing;
}

/// Кусок содержимого.
final class ContentChunk extends CoreEvent {
  const ContentChunk(this.runId, this.bytes);

  final String runId;
  final List<int> bytes;
}

/// Содержимое кончилось — или не пошло вовсе.
final class ContentEnded extends CoreEvent {
  const ContentEnded(this.runId, {this.error, this.message = ''});

  final String runId;

  /// Отказ источника — как есть; null — дочитали до конца.
  final FsError? error;

  /// Чужая беда — текстом.
  final String message;
}

/// Работа рассказывает о себе.
final class OperationProgress extends CoreEvent {
  const OperationProgress(this.runId, this.report);

  final String runId;
  final ProgressReport report;
}

/// Работа встала и ждёт человека.
///
/// Вопрос уезжает **описанием**: `Completer` через границу не поедет, а имя
/// варианта — поедет. Ответ приходит обратно [AnswerInput] по тому же имени
/// работы.
final class OperationAsked extends CoreEvent {
  const OperationAsked(this.runId, this.ask);

  final String runId;
  final AskSpec ask;
}

/// Вопрос снят: на него ответили или работа кончилась.
///
/// Без него окно вопроса осталось бы висеть после отмены работы: спрашивать
/// уже нечего, а закрыть его некому.
final class OperationAskCanceled extends CoreEvent {
  const OperationAskCanceled(this.runId);

  final String runId;
}

/// Работа кончилась — и вот чем.
final class OperationEnded extends CoreEvent {
  const OperationEnded(this.runId, this.outcome, {this.error, this.message = ''});

  final String runId;
  final OperationOutcome outcome;

  /// Отказ источника — как есть: «нет такого пути» и «нет прав» показывают
  /// по-разному.
  final FsError? error;

  /// Чужая беда — текстом: тип через границу не поедет, а текст это всё, что
  /// скажут человеку.
  final String message;
}

/// У посчитанных каталогов появился размер: строка списка → новое число.
///
/// Отдельно от списка, и это не мелочь: обход помеченного меняет по одному
/// числу в строке, а список бывает в десять тысяч строк. Номер списка нужен
/// затем же, зачем и в ссылке на строку: пока сообщение шло, каталог могли
/// перечитать, и числа тогда уже не про эти строки.
final class PanelSized extends CoreEvent {
  const PanelSized(this.panel, this.generation, this.sizes);

  final PanelId panel;
  final int generation;
  final Map<int, int> sizes;
}
