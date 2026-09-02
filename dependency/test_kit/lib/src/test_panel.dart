import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flex_commander/state/panel_controller.dart';

/// Панель на подставном провайдере.
///
/// Реестр провайдеров и движок файловых операций панель больше не подставляет
/// себе сама: чем открываются вложенные источники и каким движком выполняются
/// операции — решение сборки приложения, а не панели. Тесту это решение обычно
/// безразлично, поэтому умолчания живут здесь: один источник и обычный движок.
PanelController testPanel({
  required TreeProvider provider,
  required PanelSettings settings,
  ProviderRegistry? registry,
  TreeEditor editor = const TreeTransferEngine(),
  int sizeScanConcurrency = AppSettings.defaultSizeScanConcurrency,
}) {
  return PanelController(
    settings: settings,
    registry: registry ?? ProviderRegistry(root: provider),
    editor: editor,
    sizeScanConcurrency: () => sizeScanConcurrency,
  );
}
