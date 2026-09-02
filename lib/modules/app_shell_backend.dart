import 'package:fc_core_api/fc_core_api.dart';

/// Оболочка приложения — ядровая половина.
///
/// Одна вещь, зато та, без которой не собрать ни одной файловой операции:
/// движок переноса. Он один на приложение — состояния у него нет, а источники
/// узлы приносят с собой, в том числе разные у источника и приёмника.
class AppShellBackend implements FcBackendModule {
  const AppShellBackend();

  @override
  String get id => 'fc.shell';

  @override
  String get title => 'Application shell';

  @override
  void installBackend(BackendRegistry registry) {
    registry.service<TreeEditor>((services) => const TreeTransferEngine());
  }
}
