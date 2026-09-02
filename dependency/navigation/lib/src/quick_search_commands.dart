import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'quick_search_state.dart';

/// Команды самого поиска: при них полоса остаётся, при любой другой — уходит.
///
/// Список живёт рядом с командами, а не внутри состояния: объявляет их модуль,
/// и он же знает, что здесь перечислено всё. Ядру он отдаётся при открытии
/// полосы ([QuickSearchState.survivesCommand]).
const Set<String> quickSearchCommands = {
  QuickSearchCommand.commandId,
  QuickSearchTypeCommand.commandId,
  QuickSearchEraseCommand.commandId,
  QuickSearchStopCommand.commandId,
};

/// Быстрый поиск в панели: курсор идёт за набранным.
///
/// Клавиша из `mc` (`Ctrl-S`), и повадка та же: совпадение **с начала имени**,
/// без учёта регистра, переход мгновенный. Не «найти и показать список», а
/// «вести курсор за набранным» — каталог тот же, список тот же, меняется только
/// положение курсора.
///
/// Полоса набора живёт в **статусной области** под панелью: там для такого и
/// заведено место, и стопка в нём выкладывается столбцом — идёт работа, под ней
/// поиск, и одно другого не прячет. Само присутствие состояния и есть «режим
/// включён». Подробности — `docs/spec/file-search.md`, §2.
class QuickSearchCommand extends AppCommand {
  static const String commandId = 'panel.quickSearch';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick search';

  @override
  String get description => 'Move the cursor as you type the beginning of a name';

  @override
  Set<String> get keywords => const {'incremental search', 'find in panel', 'jump to name'};

  @override
  bool isExecutable(CommandContext context) => context.panel.nodes.isNotEmpty;

  @override
  Future<void> execute(CommandContext context) async {
    final search = searchIn(context.app);
    if (search != null) {
      // Повторное нажатие — к следующему такому же, по кругу. Образец с
      // ненайденным хвостом никуда не ведёт, и курсор остаётся на месте сам:
      // отдельного условия для этого не нужно.
      moveTo(search.panel, search.pattern, from: search.panel.cursorIndex + 1);
      return;
    }

    final view = context.app.view;
    final position = view.activeArea.status;
    if (position == null) {
      return;
    }
    // Первое нажатие только открывает полосу: курсор не двигается, потому что
    // искать ещё нечего.
    view.pushViewportContent(
      position,
      QuickSearchState(panel: context.panel, onLeave: () => leave(context.app), keeps: quickSearchCommands),
    );
  }

  /// Идущий сейчас поиск активной панели; null — режима нет.
  static QuickSearchState? searchIn(Application app) {
    final position = app.view.activeArea.status;
    if (position == null) {
      return null;
    }
    final content = app.view.contentAt(position);
    return content is QuickSearchState ? content : null;
  }

  /// Убрать полосу.
  static void leave(Application app) {
    final position = app.view.activeArea.status;
    if (position != null && app.view.contentAt(position) is QuickSearchState) {
      app.view.popViewportContent(position);
    }
  }

  /// Ведёт курсор к первому имени, начинающемуся с [pattern]; false — такого
  /// нет вовсе.
  ///
  /// Ищет от [from] и по кругу: перебор одним и тем же образцом не должен
  /// топтаться на первом попавшемся.
  static bool moveTo(Panel panel, String pattern, {required int from}) {
    final nodes = panel.nodes;
    if (nodes.isEmpty) {
      return false;
    }
    final needle = pattern.toLowerCase();
    for (var offset = 0; offset < nodes.length; offset++) {
      final index = (from + offset) % nodes.length;
      final node = nodes[index];
      // «..» — не имя файла: то же правило, что у печати буквы и у пометки.
      if (node is ParentDirNode) {
        continue;
      }
      if (node.name.toLowerCase().startsWith(needle)) {
        panel.setCursorIndex(index);
        return true;
      }
    }
    return false;
  }
}

/// Набранная буква уточняет образец быстрого поиска.
///
/// **Печатать можно всё и всегда.** Не совпало — буква всё равно встаёт в поле,
/// только уже в хвост: курсор остаётся там, где стоял, а хвост показывается
/// выделенным и стирается одним `Bsp`.
///
/// Раньше такая буква молча не принималась. Довод был про опечатку — «иначе
/// после первой же не находится ничего», — но живьём это оборачивалось хуже:
/// поле на экране, курсор в нём, нажатия уходят в никуда, и никакого ответа
/// (звонка у нас нет). Обычная причина — не опечатка, а **раскладка**, и
/// понять это можно только увидев набранное.
class QuickSearchTypeCommand extends AppCommand {
  static const String commandId = 'panel.quickSearch.type';
  static const String characterParam = 'character';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick search: type';

  @override
  String get description => 'Add a letter to what the quick search is looking for';

  @override
  bool isExecutable(CommandContext context) => QuickSearchCommand.searchIn(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final search = QuickSearchCommand.searchIn(context.app);
    final character = context.invocation.param<String>(characterParam) ?? '';
    if (search == null || character.isEmpty) {
      return;
    }

    // Пока хвост пуст, буква ещё может найтись. Появился — искать больше
    // незачем: имени, начинающегося с `ab`, нет, значит нет и с `abc`.
    final wider = '${search.matched}$character';
    // Ищем **с текущего места**, а не со следующего: уточнение образца не повод
    // уходить с имени, которое ему и так подходит.
    if (search.tail.isEmpty && QuickSearchCommand.moveTo(search.panel, wider, from: search.panel.cursorIndex)) {
      search.setPattern(matched: wider, tail: '');
      return;
    }
    search.setPattern(matched: search.matched, tail: '${search.tail}$character');
  }
}

/// `Bsp` укорачивает образец — а ненайденный хвост стирает целиком.
///
/// Хвост стирается **разом**, потому что он и набран разом: человек напечатал
/// слово не в той раскладке и хочет вернуться к последней букве, на которой
/// поиск ещё что-то находил, а не выбивать промах по одному нажатию.
///
/// Стёрли всё — полоса остаётся: стирают, чтобы набрать иначе, а не чтобы
/// выйти. И уж точно не затем, чтобы уехать в родительский каталог.
///
/// **Выполнима, пока идёт набор, — даже когда стирать уже нечего.** Условие
/// «и что-то набрано» выглядело безобидным: команда невыполнима, клавиша
/// достаётся следующей привязке, а следующая у `Bsp` — переход наверх. Живьём
/// это значило, что стёртая до конца строка уводит панель из каталога, и
/// набирать заново приходится уже не там. Пока полоса на экране, `Bsp`
/// принадлежит ей, а выходят из набора одним `Esc`.
class QuickSearchEraseCommand extends AppCommand {
  static const String commandId = 'panel.quickSearch.erase';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick search: erase';

  @override
  String get description => 'Remove the last letter from the quick search, or all of what did not match';

  @override
  bool isExecutable(CommandContext context) => QuickSearchCommand.searchIn(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final search = QuickSearchCommand.searchIn(context.app);
    if (search == null) {
      return;
    }
    // Ненайденное уходит целиком, до последней буквы, на которой поиск ещё
    // что-то находил. Курсор при этом не двигается: он и стоял на ней.
    if (search.tail.isNotEmpty) {
      search.setPattern(matched: search.matched, tail: '');
      return;
    }
    if (search.matched.isEmpty) {
      return;
    }
    final shorter = search.matched.substring(0, search.matched.length - 1);
    search.setPattern(matched: shorter, tail: '');
    if (shorter.isNotEmpty) {
      // Курсор не прыгает назад, пока имя подходит и укороченному образцу.
      QuickSearchCommand.moveTo(search.panel, shorter, from: search.panel.cursorIndex);
    }
  }
}

/// `Esc` убирает полосу; курсор остаётся там, куда дошёл.
class QuickSearchStopCommand extends AppCommand {
  static const String commandId = 'panel.quickSearch.stop';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick search: stop';

  @override
  String get description => 'Leave the quick search, keeping the cursor where it is';

  @override
  bool isExecutable(CommandContext context) => QuickSearchCommand.searchIn(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async => QuickSearchCommand.leave(context.app);
}
