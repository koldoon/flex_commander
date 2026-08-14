import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'model/os/plugin_window_service.dart';
import 'model/settings/settings_store.dart';
import 'model/tree/local/local_tree_provider.dart';
import 'state/app_controller.dart';
import 'state/panel_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginWindowService.ensureInitialized();

  final provider = LocalTreeProvider();
  final store = SettingsStore.forHome(provider.homePath);
  final settings = await store.load();

  final controller = AppController(
    left: PanelController(provider: provider, settings: settings.left),
    right: PanelController(provider: provider, settings: settings.right),
    store: store,
    settings: settings,
    window: PluginWindowService(),
  );

  runApp(FlexCommanderApp(controller: controller));

  // Окно и каталоги восстанавливаются уже после первого кадра: окно
  // показывается сразу с сохранёнными размерами, а панели заполняются
  // по мере чтения.
  unawaited(controller.start());
}
