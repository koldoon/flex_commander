import 'package:flex_commander/model/os/window_service.dart';
import 'package:flex_commander/model/settings/window_geometry.dart';

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
