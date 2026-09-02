import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';

/// Содержимое узла напрямую, без границы.
///
/// Для проверок, которым проверяемое — не разговор с ядром, а сам показ:
/// просмотрщик, разбор картинки, окно сведений. Граница у них проверяется
/// отдельно (`test/core/content_test.dart`), и тащить её в каждый виджетный
/// тест значило бы проверять одно и то же дважды.
class NodeContent implements Content {
  const NodeContent(this.node);

  final FsNode node;

  @override
  int get length => node.size;

  @override
  Stream<List<int>> read({int offset = 0}) async* {
    final provider = node.provider;
    if (provider is! FileContentProvider) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }
    yield* await (provider as FileContentProvider).openRead(node, offset: offset);
  }
}
