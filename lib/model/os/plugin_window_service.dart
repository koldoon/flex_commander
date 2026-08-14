import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../settings/window_geometry.dart';
import 'window_service.dart';

/// Реализация [WindowService] поверх `window_manager`.
class PluginWindowService with WindowListener implements WindowService {
  PluginWindowService() {
    windowManager.addListener(this);
  }

  /// Инициализация плагина. Вызывается до `runApp`.
  static Future<void> ensureInitialized() => windowManager.ensureInitialized();

  final List<void Function()> _listeners = [];

  @override
  Future<void> restore(WindowGeometry? geometry) async {
    final target = geometry ?? WindowGeometry.defaults;

    final options = WindowOptions(
      size: Size(target.width, target.height),
      minimumSize: const Size(WindowGeometry.minWidth, WindowGeometry.minHeight),
      title: 'Flex Commander',
      // Окно показывается уже с восстановленной геометрией: иначе видно, как
      // оно прыгает из положения по умолчанию в сохранённое.
      center: geometry == null,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (geometry != null) {
        await windowManager.setBounds(Rect.fromLTWH(geometry.left, geometry.top, geometry.width, geometry.height));
      }
      if (target.maximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Future<WindowGeometry?> current() async {
    final bounds = await windowManager.getBounds();
    return WindowGeometry(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
      maximized: await windowManager.isMaximized(),
    );
  }

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  @override
  void dispose() {
    windowManager.removeListener(this);
    _listeners.clear();
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  @override
  void onWindowResized() => _notify();

  @override
  void onWindowMoved() => _notify();

  @override
  void onWindowMaximize() => _notify();

  @override
  void onWindowUnmaximize() => _notify();
}
