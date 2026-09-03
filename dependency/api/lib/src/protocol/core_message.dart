import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import '../async/progress_report.dart';
import '../values/fs_error.dart';
import 'entry_ref.dart';
import 'file_entry.dart';
import 'operation_spec.dart';
import '../os/credentials.dart';
import '../os/elevation.dart';
import 'panel_state.dart';
import 'ui_settings.dart';

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

/// Ответ на вопрос о секрете; null — отказались отвечать.
///
/// Помнит ответ **ядро**: помнит тот, кто спрашивает, — иначе за запомненным
/// пришлось бы ходить через границу на каждое чтение записи из архива.
final class AnswerCredential extends CoreRequest {
  const AnswerCredential(this.askId, this.credential, {required this.realm});

  /// Какой именно вопрос: их бывает несколько подряд, а окно одно.
  final String askId;

  /// К чему он был: под этим именем ответ и запомнится.
  final String realm;

  final Credential? credential;
}

/// Ответ на предложение сделать что-то от администратора.
final class AnswerElevation extends CoreRequest {
  const AnswerElevation(this.askId, {required this.agreed});

  final String askId;
  final bool agreed;
}

/// Экранная половина настроек изменилась: окно подвинули, разделитель
/// потянули, панель переключили.
///
/// Не ответ, а сообщение: запись отложенная, и подряд идущие правки сливаются
/// в одну. Записать **сейчас** просит [SaveSettings] — этого ждут при выходе.
final class ChangeSettings extends CoreRequest {
  const ChangeSettings(this.ui);

  final UiSettings ui;
}

/// Записать настройки на диск и дождаться записи.
///
/// Ровно для выхода: там ждать обязательно — процесс уходит, и отложенному
/// таймеру сработать будет уже негде.
final class SaveSettings extends CoreRequest {
  const SaveSettings();
}

/// Уходим: записать настройки и закрыть всё, что ядро держит.
///
/// Ждать обязательно: за этим следует конец процесса, а открытый файл или
/// живое соединение пережить его не должны.
final class Shutdown extends CoreRequest {
  const Shutdown();
}

/// Начать: открыть панели там, где их оставили.
///
/// Первым делом и до всякого экрана: интерфейс подписывается на готовое, а не
/// смотрит, как оно собирается (`docs/spec/client-server.md`, §9).
final class StartCore extends CoreRequest {
  const StartCore();
}

/// Показать находки панелью — списком, смонтированным в ядре.
///
/// Список находок — источник, а не выдумка интерфейса: узлы в нём настоящие и
/// принадлежат своим провайдерам, поэтому копирование, удаление, `F3` и `F4`
/// работают над ними без единой правки. Заводится он **здесь**, где эти узлы и
/// живут; та сторона называет работу, чьи находки показывать.
final class ShowFound extends CoreRequest {
  const ShowFound(this.panel, this.runId, {this.title = ''});

  final PanelId panel;
  final String runId;

  /// Как список назвать: маска, по которой он сложился.
  final String title;
}

/// Имена в каталоге по пути — не открывая его в панели.
///
/// Ровно для дополнения по `Tab`: строка спрашивает, что лежит рядом, а панель
/// при этом остаётся там, где стояла. Скрытые не отсеиваются — кто спросил, тот
/// и решает, показывать ли их: `s` не должен предлагать `.ssh`, а `.s` обязан.
///
/// Путь считается **от панели**: `~` у сервера свой, и подставлять вместо него
/// местный было бы враньём.
final class ListNames extends CoreRequest {
  const ListNames(this.panel, this.path);

  final PanelId panel;
  final String path;
}

/// Завести оболочку там, где стоит панель, — или отдать уже заведённую.
///
/// Оболочка **одна на место**, и хозяин ей — ядро: там живёт псевдотерминал,
/// там же берётся аренда источника (`htop`, запущенный на сервере, обязан
/// дожить до своего конца, даже если панель ушла оттуда сразу). Экрану
/// достаётся разбор вывода и клавиши обратно.
///
/// [panel] null — своя машина: греют оболочку заранее, когда панелей ещё нет.
final class OpenShell extends CoreRequest {
  const OpenShell({this.panel, this.directory, this.columns = 80, this.rows = 24});

  final PanelId? panel;

  /// Откуда оболочка начнёт; учитывается только при первом запуске.
  final String? directory;

  /// Размер окна: без него `vim` и `htop` считают, что перед ними 80×24.
  final int columns;
  final int rows;
}

/// Сказать в идущую работу: отмена, ответ на вопрос.
final class TellOperation extends CoreRequest {
  const TellOperation(this.runId, this.input);

  final String runId;
  final OperationInput input;
}

/// Панель убрали из области: отпустить всё, что она держала.
///
/// Не то же, что «прервать»: работу можно прервать и остаться на месте, а
/// здесь панели больше нет — и смонтированный ради неё архив держать незачем.
final class ClosePanel extends CoreRequest {
  const ClosePanel(this.panel);

  final PanelId panel;
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

/// Список значениями — ответ на просьбу, а не событие панели.
final class CoreEntries extends CoreReply {
  const CoreEntries(this.entries);

  final List<FileEntry> entries;
}

/// Оболочка есть — вот её разговор.
final class ShellOpened extends CoreReply {
  const ShellOpened(this.runId, {required this.label, this.program = '', required this.fresh});

  /// Имя разговора. Даёт его **ядро**, а не эта сторона: оболочка одна на
  /// место, и второе имя означало бы вторую.
  final String runId;

  /// Как место называется: `localhost` или `user@host`.
  final String label;

  /// Чем оболочка запущена; пусто — не знаем (так на той стороне `ssh`).
  /// Нужно ровно уговору о метках: он у каждой оболочки свой.
  final String program;

  /// Только что запустилась. Уже жившей уговор второй раз не шлют — и ленту её
  /// не заводят заново: она у экрана и так есть.
  final bool fresh;
}

/// Ответ на рукопожатие: что у ядра есть прямо сейчас.
///
/// Панели и их списки — и ничего больше. Схемы архивов и адресов сюда не
/// поехали нарочно: решает, что делать с файлом, на котором нажали `Enter`,
/// **ядро**, и знать это интерфейсу незачем. Понадобится — приедет; заранее
/// возить то, чего никто не спрашивает, значит городить язык впрок.
final class CoreReady extends CoreReply {
  const CoreReady({required this.states, required this.listings, this.ui = const UiSettings()});

  /// Состояние каждой панели.
  final Map<PanelId, PanelState> states;

  /// И её список.
  final Map<PanelId, PanelListing> listings;

  /// Экранная половина настроек: место окна, разделитель, активная панель.
  ///
  /// Приезжает рукопожатием, а не читается вторым экземпляром файла: файл один
  /// и принадлежит ядру (`docs/spec/client-server.md`, §9).
  final UiSettings ui;
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

/// Ядру нужен секрет: пароль к архиву, к серверу, к `sudo`.
///
/// Спрашивает тот, кто работает с источником, — а показать вопрос может только
/// тот, у кого есть экран. Отсюда и событие: ядро зовёт, экран отвечает
/// [AnswerCredential] (`docs/spec/client-server.md`, §7.3).
final class CredentialAsked extends CoreEvent {
  const CredentialAsked(this.askId, this.request);

  final String askId;
  final CredentialRequest request;
}

/// Ядро предлагает сделать что-то от администратора.
///
/// Согласие спрашивается **всегда**, даже когда пароль не нужен: запомненный
/// ответ или `NOPASSWD` не должны превращать запись в системный каталог в
/// незаметное действие.
final class ElevationAsked extends CoreEvent {
  const ElevationAsked(this.askId, this.request);

  final String askId;
  final ElevationRequest request;
}

/// Работа нашла — пачкой, по ходу дела.
///
/// Своим событием, а не в отчёте о ходе: отчёт идёт на каждый каталог, а
/// находок в нём бывает ноль. По той же причине, по какой у размеров своё
/// событие: возить пустое чаще, чем нужно, — та же беда, что и возить лишнее.
final class OperationFound extends CoreEvent {
  const OperationFound(this.runId, this.entries);

  final String runId;
  final List<FileEntry> entries;
}

/// Оболочка что-то вывела — байтами, как они пришли.
///
/// Байтами, а не строками: в терминале ходит не текст, а поток с управляющими
/// последовательностями, и многобайтный символ вполне может приехать разорванным
/// между двумя порциями.
final class ShellOutput extends CoreEvent {
  const ShellOutput(this.runId, this.bytes);

  final String runId;
  final List<int> bytes;
}

/// Оболочка кончилась: `exit`, `kill`, обрыв соединения.
final class ShellExited extends CoreEvent {
  const ShellExited(this.runId, this.exitCode);

  final String runId;
  final int exitCode;
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
