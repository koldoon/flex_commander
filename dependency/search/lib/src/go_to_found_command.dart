import 'package:fc_ui_api/fc_ui_api.dart';

import 'search_results_provider.dart';

/// `Enter` в списке находок: перейти к объекту в его каталоге.
///
/// Не открыть его: в результатах поиска чаще нужно первое — посмотреть, где
/// файл лежит и что рядом с ним. Открыть его оттуда можно и `F3`.
class GoToFoundCommand extends AppCommand {
  static const String commandId = 'search.goToFound';

  @override
  String get id => commandId;

  @override
  String get label => 'Go to found file';

  @override
  String get description => 'Leave the search results for the directory the file lies in';

  @override
  Set<String> get keywords => const {'reveal', 'locate', 'results'};

  /// Только в списке находок: в обычном каталоге `Enter` делает то, что и
  /// всегда, — привязка тогда невыполнима и достаётся навигации.
  @override
  bool isExecutable(CommandContext context) {
    final panel = context.panel;
    final entry = panel.currentEntry;
    // Находки узнаются по схеме источника, а не по его типу: типа этой стороне
    // не видно, а схема приезжает снимком.
    return panel.source.scheme == SearchResultsProvider.schemeName &&
        entry != null &&
        !entry.isParent &&
        entry.directoryPath.isNotEmpty;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final entry = panel.currentEntry;
    if (entry == null || entry.directoryPath.isEmpty) {
      return;
    }
    // Каталог находки — её же поле: складывать путь умеет только источник, и
    // он это уже сделал.
    await panel.openPath(entry.directoryPath);
    panel.setCursorToName(entry.name);
  }
}
