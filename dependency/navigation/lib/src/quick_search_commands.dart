import 'package:fc_api/fc_api.dart';

/// Быстрый поиск в панели: курсор идёт за набранным.
///
/// Клавиша из `mc` (`Ctrl-S`), и повадка та же: совпадение **с начала имени**,
/// без учёта регистра, переход мгновенный. Не «найти и показать список», а
/// «вести курсор за набранным» — каталог тот же, список тот же, меняется только
/// положение курсора.
///
/// Правило поиска живёт здесь, а не в панели: панель держит образец
/// ([Panel.quickSearch]) и показывает его, а куда идти курсору — решение того,
/// кто разбирает клавиши. Подробности — `docs/spec/file-search.md`, §2.
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
    final panel = context.panel;
    final pattern = panel.quickSearch;
    if (pattern == null) {
      // Первое нажатие только включает режим: курсор не двигается, потому что
      // искать ещё нечего.
      panel.setQuickSearch('');
      return;
    }
    // Повторное — к следующему такому же, по кругу.
    moveTo(panel, pattern, from: panel.cursorIndex + 1);
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
/// **Не совпало — буква не принимается.** Курсор остаётся, образец не растёт:
/// иначе после первой же опечатки не находится ничего, и стирать приходится
/// вслепую.
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
  bool isExecutable(CommandContext context) => context.panel.quickSearch != null;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final character = context.invocation.param<String>(characterParam) ?? '';
    final pattern = panel.quickSearch;
    if (character.isEmpty || pattern == null) {
      return;
    }

    final wider = '$pattern$character';
    // Ищем **с текущего места**, а не со следующего: уточнение образца не повод
    // уходить с имени, которое ему и так подходит.
    if (QuickSearchCommand.moveTo(panel, wider, from: panel.cursorIndex)) {
      panel.setQuickSearch(wider);
    }
  }
}

/// `Backspace` укорачивает образец.
///
/// Укоротили до пустого — режим остаётся включённым: человек стирает, чтобы
/// набрать иначе, а не чтобы выйти.
class QuickSearchEraseCommand extends AppCommand {
  static const String commandId = 'panel.quickSearch.erase';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick search: erase';

  @override
  String get description => 'Remove the last letter from the quick search';

  @override
  bool isExecutable(CommandContext context) => context.panel.quickSearch?.isNotEmpty ?? false;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final pattern = panel.quickSearch;
    if (pattern == null || pattern.isEmpty) {
      return;
    }
    final shorter = pattern.substring(0, pattern.length - 1);
    panel.setQuickSearch(shorter);
    if (shorter.isNotEmpty) {
      QuickSearchCommand.moveTo(panel, shorter, from: panel.cursorIndex);
    }
  }
}

/// `Esc` выходит из режима; курсор остаётся там, куда дошёл.
class QuickSearchStopCommand extends AppCommand {
  static const String commandId = 'panel.quickSearch.stop';

  @override
  String get id => commandId;

  @override
  String get label => 'Quick search: stop';

  @override
  String get description => 'Leave the quick search, keeping the cursor where it is';

  @override
  bool isExecutable(CommandContext context) => context.panel.quickSearch != null;

  @override
  Future<void> execute(CommandContext context) async => context.panel.setQuickSearch(null);
}
