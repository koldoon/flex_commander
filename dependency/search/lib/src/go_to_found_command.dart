import 'package:fc_core_api/fc_core_api.dart';
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
    return panel.provider is SearchResultsProvider &&
        panel.currentNode is! ParentDirNode &&
        panel.currentNode?.parentDirectory != null;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final panel = context.panel;
    final node = panel.currentNode;
    final directory = node?.parentDirectory;
    if (node == null || directory == null) {
      return;
    }
    await panel.open(directory);
    panel.setCursorToName(node.name);
  }
}
