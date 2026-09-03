import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'find_files_command.dart';
import 'go_to_found_command.dart';
import 'search_query.dart';
import 'search_run.dart';
import 'search_work.dart';

/// Поиск по дереву и работа с найденным.
///
/// Один класс на обе стороны. Обход живёт в ядре, потому что там живут
/// источники: `listChildren` — это поход на диск, в архив или по сети. Наружу
/// находки едут значениями, по ходу дела
/// (`docs/spec/client-server.md`, §5.1.6).
///
/// Быстрый поиск в панели живёт не здесь, а в навигации: он водит курсор по
/// списку, который и так на экране, и общего с обходом дерева у него нет
/// ничего (`spec/file-search.md`, §8).
class FileSearch implements FcBackendModule, FcFrontendModule {
  const FileSearch();

  static const String moduleId = 'fc.search';

  @override
  String get id => 'fc.search';

  @override
  String get title => 'File search';

  @override
  void installBackend(BackendRegistry registry) {
    registry.operation(SearchWork.kind, (services) => searching());
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.command((context) => FindFilesCommand());
    registry.command((context) => GoToFoundCommand());

    // Привычка Total Commander.
    registry.binding(KeyBinding('Alt-F7', FindFilesCommand.commandId));
    // `Enter` — **раньше** навигации, потому и модуль объявлен раньше неё.
    // Вне списка находок команда невыполнима, и `Enter` открывает объект, как
    // и всегда.
    registry.binding(KeyBinding('Enter', GoToFoundCommand.commandId));
  }

  /// Работа: где искать — единственная цель заявки, о чём — её доводы.
  static Operation<OperationInputs, void> searching() {
    return TaskOperation<OperationInputs, void>((op, inputs) async {
      final where = inputs.targets.whereType<DirectoryNode>().firstOrNull;
      if (where == null) {
        // Искать негде: каталог уехал из-под ног, пока окно было открыто.
        throw const FsError('', FsErrorKind.notFound);
      }
      final query = SearchQuery(
        mask: inputs.option<String>(SearchWork.maskOption) ?? '',
        recursive: inputs.option<bool>(SearchWork.recursiveOption) ?? true,
        hidden: inputs.option<bool>(SearchWork.hiddenOption) ?? false,
      );
      await op.delegate(SearchRun.from(where, onFound: inputs.onFound), query);
    });
  }
}
