import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

import 'search_query.dart';
import 'search_run.dart';
import 'search_work.dart';

/// Поиск по дереву — ядровая половина.
///
/// Обход живёт здесь, потому что здесь живут источники: `listChildren` — это
/// поход на диск, в архив или по сети, и заводить ради него второй путь к
/// дереву по ту сторону границы было бы враньём. Наружу едут находки
/// значениями, по ходу дела (`docs/spec/client-server.md`, §5.1.6).
class FileSearchBackend implements FcBackendModule {
  const FileSearchBackend();

  @override
  String get id => 'fc.search';

  @override
  String get title => 'File search';

  @override
  void installBackend(BackendRegistry registry) {
    registry.operation(SearchWork.kind, (services) => searching());
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
