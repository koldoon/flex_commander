import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import '../values/fs_error.dart';
import 'entry_ref.dart';
import 'file_entry.dart';
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

/// Ответ на рукопожатие: что у ядра есть прямо сейчас.
final class CoreReady extends CoreReply {
  const CoreReady({required this.states, required this.listings, required this.schemes, required this.addresses});

  /// Состояние каждой панели.
  final Map<PanelId, PanelState> states;

  /// И её список.
  final Map<PanelId, PanelListing> listings;

  /// Расширения, которыми открываются вложенные источники, и схемы адресов:
  /// то, что известно **до всякого разговора**. Спрашивать их сообщением
  /// значило бы сделать асинхронным то, что готово раньше первой панели.
  final Map<String, String> schemes;
  final Set<String> addresses;
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
