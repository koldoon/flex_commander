import '../panel/column_spec.dart';
import '../settings/path_step.dart';
import '../panel/rows_kind.dart';
import '../panel/sort_spec.dart';
import '../async/progress_report.dart';
import '../values/fs_error.dart';
import '../values/node_attributes.dart';
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

/// Просьба, обращённая к одной панели.
///
/// Общий признак, а не поле у каждой: панель бывает **убрана**, а просьба к ней
/// — уже в пути. Ядро отвечает такой тишиной, и проверить это надо один раз, на
/// входе, а не двадцатью проверками в разборе
/// (`docs/spec/client-server.md`, §5).
abstract interface class PanelRequest {
  PanelId get panel;
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
final class OpenPath extends CoreRequest implements PanelRequest {
  const OpenPath(this.panel, this.path, {this.allowConnect = true});

  @override
  final PanelId panel;
  final String path;
  final bool allowConnect;
}

/// Войти в объект: каталог, архив, ссылка на каталог.
///
/// Ответом приходит то, во что войти нельзя (обычный файл), — им займётся
/// команда; null означает, что переход выполнен.
final class OpenEntry extends CoreRequest implements PanelRequest {
  const OpenEntry(this.panel, this.entry);

  @override
  final PanelId panel;
  final EntryRef entry;
}

/// На уровень вверх; курсор встаёт на объект, через который вошли.
final class GoUp extends CoreRequest implements PanelRequest {
  const GoUp(this.panel);

  @override
  final PanelId panel;
}

/// Шаг по истории переходов этой сессии
/// (`docs/spec/session-history.md`).
///
/// Одним сообщением на три хода: назад, вперёд и прыжок к названному шагу —
/// это одно действие с разным адресом, и разводить их по трём сообщениям
/// значило бы трижды написать одно и то же.
final class WalkHistory extends CoreRequest implements PanelRequest {
  const WalkHistory(this.panel, this.where, {this.index = 0});

  @override
  final PanelId panel;
  final HistoryWalk where;

  /// Номер шага — только для [HistoryWalk.toStep].
  final int index;
}

/// Куда шагнуть по истории.
enum HistoryWalk {
  back,
  forward,

  /// К названному номером шагу: ход по истории, «вперёд» не обрезается.
  toStep,
}

/// Пройденное сессией — списком.
///
/// Просьбой, а не событием: список нужен один раз, когда открывают окно
/// выбора, и возить его в каждом снимке было бы работой впустую
/// (`docs/spec/session-history.md`, §6).
final class AskHistory extends CoreRequest implements PanelRequest {
  const AskHistory(this.panel);

  @override
  final PanelId panel;
}

/// Перечитать каталог, сохранив курсор и пометку.
final class Reload extends CoreRequest implements PanelRequest {
  const Reload(this.panel);

  @override
  final PanelId panel;
}

/// Курсор стоит вот на этой строке — **факт**, а не просьба.
///
/// Курсор принадлежит экрану: там его рисуют, там же решают, куда он идёт с
/// клавиши, страницы и щелчка. Ядру он нужен для трёх дел — шаг истории, файл
/// настроек и «где панель стоит» у дерева, — и ни одному из них не нужен
/// номер строки, и ни одному — в тот же миг
/// (`docs/spec/client-server.md`, §5.6).
///
/// Поэтому ни ответа, ни номера заявки здесь нет: сказали — и пошли дальше.
/// Ядро, не нашедшее такой строки, держит прежнюю: список у него мог ещё не
/// смениться, а выдумывать себе место оно не станет.
final class CursorAt extends CoreRequest implements PanelRequest {
  const CursorAt(this.panel, this.path);

  @override
  final PanelId panel;

  /// Путь строки; пусто — строки нет (пустой список).
  final String path;
}

/// Заменить пометку целиком — путями.
///
/// Одна просьба на все способы пометить: по маске, всё, снять. Развернуть маску
/// в пути может и интерфейс — список у него есть.
///
/// Путями, а не именами: помеченное бывает из разных ветвей дерева, и имя там
/// опознаёт не объект, а совпадение (`docs/spec/panel-view-tree.md`, §7).
/// Названный путь ядро ищет среди узлов каталога, а не найденный оставляет
/// прежним узлом пометки — так пометка соседней ветви переживает уход курсора.
/// [seq] растёт с каждой заявкой этой стороны. Ядро возвращает его в стейте, и
/// зеркало по нему отличает свежее подтверждение от опоздавшего: пометка
/// применяется **сразу**, а подтверждения на первые заявки приходят, когда
/// помечено уже больше, — и слушать их значит отбирать помеченное
/// (`docs/spec/client-server.md`, §5.5).
final class SetMarks extends CoreRequest implements PanelRequest {
  const SetMarks(this.panel, this.paths, this.seq, {this.by = MarkChange.person});

  @override
  final PanelId panel;
  final Set<String> paths;
  final int seq;

  /// Кто меняет пометку: человек или работа.
  final MarkChange by;
}

/// Кто поменял пометку.
///
/// Признак, а не догадка по времени: снятие пометки отменяет обход размера —
/// человек передумал, — но **та же** пометка снимается и в конце работы,
/// которая по ней шла. Отличить одно от другого догадками нельзя, а цена
/// ошибки — выброшенные полторы минуты обхода
/// (`docs/spec/directory-sizes.md`, §12.5).
enum MarkChange {
  /// Человек: нажал клавишу, щёлкнул мышью, применил маску.
  person,

  /// Работа: скопировала помеченное и снимает пометку за собой.
  work,
}

/// Показать каталог, **не открывая** его: за курсором вида идёт каталог, а не
/// чтение.
///
/// Просит вид со своей навигацией — дерево: его курсор встал на объект, и
/// каталог панели теперь тот, в котором объект лежит
/// (`docs/spec/panel-view-tree.md`, §3). От [OpenPath] отличается тремя вещами:
/// панель не занята, пометка не снимается, а список подтягивается тихо — тот
/// же каталог вид только что прочитал сам.
final class FollowCursor extends CoreRequest implements PanelRequest {
  const FollowCursor(this.panel, this.directory, this.name);

  @override
  final PanelId panel;

  /// Каталог, в котором лежит объект под курсором вида.
  final String directory;

  /// Имя объекта: на него встаёт курсор панели, и без пометки он же цель `F5`.
  final String name;
}

/// Как показывать список: сортировка, колонки, скрытые.
final class Arrange extends CoreRequest implements PanelRequest {
  const Arrange(this.panel, {this.sort, this.columns, this.showHidden, this.view, this.rows});

  @override
  final PanelId panel;
  final SortSpec? sort;

  /// Раскладка, какой её видит экран, — а видит он только объявленное.
  /// Колонку выключенного модуля ядро возвращает на место само
  /// (`ColumnLayout.merge`, `docs/spec/column-registry.md`, §4.3).
  final ColumnLayout? columns;
  final bool? showHidden;

  /// Чем показывать каталог; null — вид не трогаем.
  final String? view;

  /// Чем набирать строки; null — набор не трогаем.
  ///
  /// Говорит это **вид**: ядро не знает ни одного вида по имени, оно знает
  /// набор строк (`docs/spec/panel-node-list.md`, §3).
  final RowsKind? rows;
}

/// Запомнить, насколько список промотан.
///
/// Сообщением, а не просьбой: это положение, а не настройка, и ответа на него
/// не ждут. Ядро его только хранит и возвращает — как и имя вида.
final class ScrollTo extends CoreRequest implements PanelRequest {
  const ScrollTo(this.panel, this.offset);

  @override
  final PanelId panel;
  final double offset;
}

/// Раскрыть или свернуть ветвь по пути.
///
/// Сообщением, а не просьбой: ответа не ждут, новые строки приедут списком.
/// Путь — потому что строки живут путями, а узлы после чтения другие.
final class ExpandRow extends CoreRequest implements PanelRequest {
  const ExpandRow(this.panel, this.path, {required this.expanded, this.deep = false});

  @override
  final PanelId panel;

  /// Путь ветви; пусто вместе с [deep] — всё дерево.
  final String path;
  final bool expanded;

  /// Вместе со всем, что под ней (`docs/spec/panel-view-tree.md`, §6а).
  final bool deep;
}

/// Сходить по ссылке: курсор встаёт на то, куда она ведёт.
///
/// Отдельно от входа: в дереве ссылку не раскрывают (увела бы в цикл), а
/// перейти к цели — можно (`docs/spec/panel-view-tree.md`, §4а).
final class FollowLink extends CoreRequest implements PanelRequest {
  const FollowLink(this.panel, this.path);

  @override
  final PanelId panel;

  /// Путь строки-ссылки.
  final String path;
}

/// Посчитать размеры всех каталогов текущего каталога.
final class MeasureDirectories extends CoreRequest implements PanelRequest {
  const MeasureDirectories(this.panel);

  @override
  final PanelId panel;
}

/// Строка состояния панели, выставленная командой.
///
/// Строка одна на всех — пишут в неё и ядро, и команды, — поэтому и живёт она
/// там же, где остальное состояние. Уходит просьба не дожидаясь ответа, а
/// зеркало пишет к себе сразу: текст должен появиться в тот же кадр, в котором
/// команда его выставила.
final class SetStatusText extends CoreRequest implements PanelRequest {
  const SetStatusText(this.panel, this.text);

  @override
  final PanelId panel;
  final String? text;
}

/// Заголовок панели, выставленный командой; null — показывается путь.
final class SetHeaderText extends CoreRequest implements PanelRequest {
  const SetHeaderText(this.panel, this.text);

  @override
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

/// Атрибуты объекта: режим, даты, владелец, расширенные атрибуты.
///
/// Просьбой, а не частью состояния строки: список бывает в десять тысяч строк,
/// и возить в каждой то, на что смотрят раз в неделю, — работа впустую
/// (`docs/spec/client-server.md`, §4.3). Читаются они **заново**: в
/// `FileEntry.attributes` лежит режим с последнего чтения каталога, и править
/// по нему значило бы вернуть файлу права, которых у него уже нет.
final class ReadAttributes extends CoreRequest {
  const ReadAttributes(this.entry);

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

/// Имена в каталоге по пути — не открывая его в панели.
///
/// Ровно для дополнения по `Tab`: строка спрашивает, что лежит рядом, а панель
/// при этом остаётся там, где стояла. Скрытые не отсеиваются — кто спросил, тот
/// и решает, показывать ли их: `s` не должен предлагать `.ssh`, а `.s` обязан.
///
/// Путь считается **от панели**: `~` у сервера свой, и подставлять вместо него
/// местный было бы враньём.
final class ListNames extends CoreRequest implements PanelRequest {
  const ListNames(this.panel, this.path);

  @override
  final PanelId panel;
  final String path;
}

/// Размеры каталогов, которые панель успела посчитать.
///
/// Просьбой, а не событием: суммы подкаталогов копятся по ходу одного обхода, и
/// возить их все на каждое движение курсора было бы работой впустую
/// (`docs/spec/client-server.md`, §4.3). Спрашивает тот, кто показывает дерево:
/// ему нужны размеры ровно тех ветвей, что сейчас на экране.
///
/// Неизвестного в ответе нет: чего панель не считала, того в карте и не будет.
final class AskSizes extends CoreRequest implements PanelRequest {
  const AskSizes(this.panel, this.paths);

  @override
  final PanelId panel;
  final List<String> paths;
}

/// Цели значениями: помеченное, а без пометки — строка под курсором.
///
/// То самое, что развернёт `Targets.marked`, — и спрашивается ровно затем,
/// чтобы окно не расходилось с работой (`docs/spec/operation-targets.md`, §3).
///
/// Просьбой, а не частью состояния: состояние едет на каждое движение курсора,
/// и возить в нём весь помеченный каталог — работа впустую
/// (`docs/spec/client-server.md`, §4.3). Счёт этой стороне и без того известен:
/// пути помеченного приезжают полностью.
final class ListTargets extends CoreRequest implements PanelRequest {
  const ListTargets(this.panel, {required this.under});

  @override
  final PanelId panel;

  /// Строка, которой отвечать, если не помечено ничего, — та, что у
  /// спрашивающего под курсором. Ядро своего курсора для этого не
  /// спрашивает: он принадлежит экрану (`docs/spec/client-server.md`, §5.6).
  final EntryRef? under;
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

/// Завести ещё одну сессию панели — по образцу названной.
///
/// По образцу, а не «пустую»: обоим потребителям нужно ровно это — спутник
/// комбинированного вида встаёт там же, где панель, а новая вкладка
/// открывается на текущем каталоге (`docs/spec/panel-sessions.md`, §4).
///
/// Кто где показан, ядро не знает и не решает: оно заводит сессию и отдаёт её
/// личность.
final class OpenPanel extends CoreRequest {
  const OpenPanel(this.like);

  final PanelId like;
}

/// Показали сессию, которую при запуске не читали, — прочитать её каталог.
///
/// Ленивое чтение (`docs/spec/panel-sessions.md`, §6): сессии заводятся все, а
/// каталог читается у показанных. Уже прочитанной просьба ничего не стоит —
/// перечитывания она не значит.
final class RestorePanel extends CoreRequest implements PanelRequest {
  const RestorePanel(this.panel);

  @override
  final PanelId panel;
}

/// Панель убрали из области: отпустить всё, что она держала.
///
/// Не то же, что «прервать»: работу можно прервать и остаться на месте, а
/// здесь панели больше нет — и смонтированный ради неё архив держать незачем.
final class ClosePanel extends CoreRequest implements PanelRequest {
  const ClosePanel(this.panel);

  @override
  final PanelId panel;
}

/// Прервать то, чем панель занята.
final class CancelWork extends CoreRequest implements PanelRequest {
  const CancelWork(this.panel);

  @override
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

/// Шаги сессии от старого к новому и номер того, на котором стоим.
final class CoreHistory extends CoreReply {
  const CoreHistory(this.steps, this.index);

  final List<PathStep> steps;

  /// Где в этом ряду сессия стоит сейчас; −1 — истории нет вовсе.
  final int index;
}

/// Вошли (null) или войти нельзя — вот во что.
final class CoreEntered extends CoreReply {
  const CoreEntered(this.entry);

  final FileEntry? entry;
}

/// Да или нет.
/// Чем кончилось раскрытие вглубь: сколько ветвей открыто и упёрлось ли в
/// предел.
///
/// Ответом, а не событием: сказать об этом надо тому, кто просил, и один раз —
/// тостом. В строке состояния такое сообщение висело бы, пока его не сменят
/// (`docs/spec/panel-view-tree.md`, §6а).
final class CoreExpanded extends CoreReply {
  const CoreExpanded({required this.opened, required this.stopped});

  final int opened;

  /// Предел достигнут: дальше человек раскрывает сам.
  final bool stopped;
}

final class CoreFlag extends CoreReply {
  const CoreFlag(this.value);

  final bool value;
}

/// Список значениями — ответ на просьбу, а не событие панели.
final class CoreEntries extends CoreReply {
  const CoreEntries(this.entries);

  final List<FileEntry> entries;
}

/// Атрибуты объекта — те, что источник о нём знает.
///
/// Не знает ничего — приезжает [NodeAttributes.unknown], и окно показывает
/// поля погашенными. Не смог ответить — это [CoreFailed]: «отказали в доступе»
/// и «править нечем» — разные ответы, и путать их нельзя.
final class CoreAttributes extends CoreReply {
  const CoreAttributes(this.attributes);

  final NodeAttributes attributes;
}

/// Посчитанные размеры: путь каталога — сумма его содержимого.
///
/// [partial] — те из них, чей обход ещё идёт: число вырастет. Без этого
/// половина неотличима от настоящего, и остановленный подсчёт оставлял бы её
/// в колонке навсегда.
final class CoreSizes extends CoreReply {
  const CoreSizes(this.sizes, {this.partial = const {}});

  final Map<String, int> sizes;
  final Set<String> partial;
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

/// Сессия заведена: её личность и первое состояние.
///
/// Состояние и список едут вместе с ответом, а не отдельным событием: зеркалу
/// нечего было бы показывать между «завели» и «рассказали».
final class PanelOpened extends CoreReply {
  const PanelOpened(this.panel, this.state, this.listing);

  final PanelId panel;
  final PanelState state;
  final PanelListing listing;
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

/// У этих каталогов размер изменился — **факт, а не значение**.
///
/// Значение спрашивают (`AskSizes`), и спрашивают в ответ на это событие. Так
/// показанное всегда верно: пока сообщение шло и пока та сторона до него
/// добралась, обход ушёл вперёд, и число, приехавшее внутри события, было бы
/// вчерашним. Гонки при этом не страшны — худшее, что бывает, лишняя
/// перерисовка (`docs/spec/client-server.md`, §4.3а).
///
/// Адрес — **путь** каталога. Размер принадлежит каталогу, а не месту в списке:
/// список перечитывается на каждый шаг курсора по дереву, узлы становятся
/// новыми, и всякая привязка к строке после первого же чтения либо умирает,
/// либо садится на чужую строку — оба раза это было видно живьём.
final class PanelSized extends CoreEvent {
  const PanelSized(this.panel, this.paths);

  final PanelId panel;

  /// Пути каталогов, чьё число изменилось с прошлого сообщения.
  final Set<String> paths;
}
