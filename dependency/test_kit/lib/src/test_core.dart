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

  // Сессии заводятся по файлу, показанные — первыми: им и достаются личности
  // `PanelId.left` и `PanelId.right` (`docs/spec/panel-slots.md`, §5). То же
  // самое делает сборка приложения, и делать иначе здесь значило бы проверять
  // не то приложение.
  final left = PanelSession(settings: settings.left, registry: registry, editor: editor);
  final right = PanelSession(settings: settings.right, registry: rightRegistry, editor: editor);
  final more = <PanelSession>[];
  final layout = <SlotLayout>[];

  for (var side = 0; side < settings.slots.length; side++) {
    final slot = settings.slots[side];
    final sideRegistry = side == 0 ? registry : rightRegistry;
    final shown = slot.current.clamp(0, slot.panels.length - 1);
    final ids = <PanelId>[];
    for (var i = 0; i < slot.panels.length; i++) {
      if (i == shown) {
        ids.add(side == 0 ? PanelId.left : PanelId.right);
        continue;
      }
      ids.add(PanelId(more.length + 2));
      more.add(PanelSession(settings: slot.panels[i], registry: sideRegistry, editor: editor));
    }
    layout.add(SlotLayout(panels: ids, current: shown));
  }

  final sessions = {
    PanelId.left: left,
    PanelId.right: right,
    for (var i = 0; i < more.length; i++) PanelId(i + 2): more[i],
  };

  final core = CoreServer(
    left: left,
    right: right,
    more: more,
    // Сессии заводятся тем же, чем и первые: слот умеет держать несколько
    // (`docs/spec/panel-slots.md`).
    createSession: (settings) => PanelSession(settings: settings, registry: registry, editor: editor),
    registry: registry,
    editor: editor,
    settings: SettingsHub(
      store: store,
      stored: settings,
      panelSettings: (panel) => sessions[panel]?.settings,
      slots: layout,
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
    more: [for (var i = 0; i < more.length; i++) mirror(PanelId(i + 2), more[i])],
    slots: layout,
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
