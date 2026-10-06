import 'package:flutter/foundation.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

/// Окно в памяти: помнит, что ему велели восстановить, и умеет изображать
/// перемещение пользователем.
class FakeWindowService implements WindowService {
  FakeWindowService([this.geometry]);

  /// Текущая геометрия «окна».
  WindowGeometry? geometry;

  /// С какой геометрией окно восстанавливали при запуске.
  WindowGeometry? restored;
  bool restoreCalled = false;

  final List<void Function()> _listeners = [];

  @override
  Future<void> restore(WindowGeometry? geometry) async {
    restoreCalled = true;
    restored = geometry;
    this.geometry = geometry ?? this.geometry;
  }

  @override
  Future<WindowGeometry?> current() async => geometry;

  /// Сколько раз окно принимались двигать за полосу.
  int dragCount = 0;
  bool maximized = false;

  @override
  Future<void> startDrag() async => dragCount++;

  @override
  Future<void> toggleMaximized() async => maximized = !maximized;

  /// Окно в системном полноэкранном режиме.
  bool fullScreen = false;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen(bool value) async => fullScreen = value;

  /// Яркость рамы: тесту она нужна не для вида, а чтобы проверить, что
  /// оформление и рама не разъезжаются.
  Brightness? brightness;

  @override
  Future<void> setBrightness(Brightness value) async => brightness = value;

  /// Пользователь подвинул окно или изменил его размер.
  void moveTo(WindowGeometry value) {
    geometry = value;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  @override
  void dispose() => _listeners.clear();
}
