import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

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
      // Полоса заголовка убирается **до** того, как окно ставят на место.
      // Системной полосы у нас нет: её место занимает содержимое, а двигают
      // окно за полосу, которую рисует шелл. Светофор остаётся — закрытие,
      // сворачивание и разворот привычнее системные, и своих кнопок для них
      // заводить незачем.
      //
      // Порядок здесь — не вкусовщина. Скрытие полосы меняет рамку окна: оно
      // оседает ровно на её высоту (32 точки), и поставленные до этого
      // размеры перестают совпадать с тем, что потом вернёт `getBounds`.
      // Разница уходила в настройки, и окно худело с каждым запуском —
      // 632, 600, 568 (поймано живьём 14 сентября 2026).
      //
      // Стиль назначается, пока окно спрятано: сделай это позже — при запуске
      // мелькнёт системная полоса.
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
      if (geometry != null) {
        await windowManager.setBounds(Rect.fromLTWH(geometry.left, geometry.top, geometry.width, geometry.height));
      }
      if (target.maximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });

    // Показанное окно проверяется и, если нужно, ставится ещё раз.
    //
    // До показа система вправе поставить окно по-своему: `setBounds` спрятанному
    // окну она принимает молча и не применяет — положение из настроек так и не
    // доезжало, окно вставало там, куда его определила система
    // (поймано живьём 15 сентября 2026 трассировкой запуска).
    if (geometry != null && !target.maximized) {
      await _insist(geometry);
    }
  }

  /// Поставить окно и убедиться, что оно встало.
  ///
  /// Одна попытка вдогонку, а не цикл: не вышло дважды — значит мешает
  /// система (окно упёрлось в край экрана, монитор отключили), и спорить с ней
  /// бесполезно.
  Future<void> _insist(WindowGeometry geometry) async {
    final wanted = Rect.fromLTWH(geometry.left, geometry.top, geometry.width, geometry.height);
    final now = await windowManager.getBounds();
    if ((now.left - wanted.left).abs() <= 1 && (now.top - wanted.top).abs() <= 1) {
      return;
    }
    await windowManager.setBounds(wanted);
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
  Future<void> startDrag() => windowManager.startDragging();

  @override
  Future<void> toggleMaximized() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
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
