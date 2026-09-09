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
import 'package:flex_commander/ui/session_mirror.dart';

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

  // Сессии заводятся по файлу — по порядку наборов и столбцов в них; личности
  // выдаются тем же порядком (`docs/spec/panel-sessions.md`, §4). Правый
  // источник достаётся тому набору, что показан справа: подставная правая
  // панель — приём проверок, а не правило.
  final rightShown = settings.groupAt(1);
  final sessions = <PanelId, PanelSession>{};
  final layout = <PanelLayout>[];

  for (final group in settings.panels) {
    final ids = <PanelId>[];
    for (final session in group.sessions) {
      final id = PanelId(sessions.length);
      sessions[id] = PanelSession(
        settings: session,
        registry: identical(group, rightShown) ? rightRegistry : registry,
        editor: editor,
      );
      ids.add(id);
    }
    layout.add(PanelLayout(sessions: ids, current: group.current.clamp(0, ids.length - 1), name: group.name));
  }

  final core = CoreServer(
    sessions: sessions,
    // Сессии заводятся тем же, чем и первые: набор умеет держать несколько
    // (`docs/spec/panel-sessions.md`).
    createSession: (settings) => PanelSession(settings: settings, registry: registry, editor: editor),
    registry: registry,
    editor: editor,
    settings: SettingsHub(
      store: store,
      stored: settings,
      panelSettings: (panel) => sessions[panel]?.settings,
      panels: layout,
      shown: settings.shown,
      saveDelay: saveDelay,
    ),
  );
  final Link link = LoopbackLink(core);

  SessionMirror mirror(PanelId id, PanelSession session) => SessionMirror(
    id: id,
    link: link,
    state: session.state,
    listing: PanelListing(generation: session.generation, entries: session.entries),
  );

  return AppController(
    sessions: [for (final entry in sessions.entries) mirror(entry.key, entry.value)],
    panels: layout,
    shown: settings.shown,
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

  PanelSession get leftSession => sessionOf(left.id);

  PanelSession get rightSession => sessionOf(right.id);
}
