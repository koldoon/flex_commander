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
import 'package:flex_commander/ui/panel_mirror.dart';

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

  PanelMirror mirror(PanelId id, PanelSession session) => PanelMirror(
    id: id,
    link: link,
    state: session.state,
    listing: PanelListing(generation: session.generation, entries: session.entries),
  );

  return AppController(
    left: mirror(PanelId.left, left),
    right: mirror(PanelId.right, right),
    core: core,
    link: link,
    settings: settings,
    commands: commands ?? CommandRegistry(),
    window: window,
  );
}

/// Сеансы панелей — со стороны ядра.
///
/// Для проверок, которые говорят об узлах, провайдерах и монтировании: всё это
/// живёт по ту сторону границы, и спрашивать о нём зеркало бессмысленно — у
/// него есть только то, о чём ядро рассказало.
extension CoreSessions on AppController {
  PanelSession sessionOf(PanelId panel) => core!.session(panel);

  PanelSession get leftSession => sessionOf(PanelId.left);

  PanelSession get rightSession => sessionOf(PanelId.right);
}
