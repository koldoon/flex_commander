import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/core/settings_hub.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/panel_controller.dart';

/// Приложение с обеими сторонами — но без модулей.
///
/// Между [testPanel] (одна панель) и `testApp` (весь граф зависимостей): здесь
/// собрано ровно то, что нужно, чтобы проверять само приложение — сеансы
/// панелей, ядро с его настройками, петля и переходники поверх неё.
///
/// Ядро настоящее, потому что без него проверять нечего: панели восстанавливает
/// оно, настройки пишет тоже оно, и «приложение сохранило настройки» — это
/// разговор через границу, а не вызов метода
/// (`docs/spec/client-server.md`, §9).
AppController testCore({
  required TreeProvider provider,
  required AppSettings settings,
  required SettingsStore store,
  TreeProvider? rightProvider,
  CommandRegistry? commands,
  WindowService? window,
  Duration saveDelay = SettingsHub.defaultSaveDelay,
}) {
  final registry = ProviderRegistry(root: provider);
  final rightRegistry = rightProvider == null ? registry : ProviderRegistry(root: rightProvider);
  const editor = TreeTransferEngine();

  final left = PanelSession(settings: settings.left, registry: registry, editor: editor);
  final right = PanelSession(settings: settings.right, registry: rightRegistry, editor: editor);
  final sessions = {PanelId.left: left, PanelId.right: right};

  final core = CoreServer(
    left: left,
    right: right,
    registry: registry,
    editor: editor,
    settings: SettingsHub(
      store: store,
      stored: settings,
      panelSettings: (panel) => sessions[panel]!.settings,
      saveDelay: saveDelay,
    ),
  );
  final Link link = LoopbackLink(core);

  return AppController(
    left: PanelController(PanelId.left, left, link: link),
    right: PanelController(PanelId.right, right, link: link),
    core: core,
    link: link,
    settings: settings,
    commands: commands ?? CommandRegistry(),
    providers: registry,
    window: window,
  );
}
