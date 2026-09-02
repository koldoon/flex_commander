import 'package:fc_api/fc_api.dart';

/// Окно приложения: восстановление геометрии при старте и уведомления о том,
/// что пользователь его подвинул или изменил размер.
///
/// Интерфейс отделён от реализации намеренно: плагин работает через
/// платформенные каналы, которых в тестах нет, а логика сохранения должна
/// проверяться без окна вообще.
abstract interface class WindowService {
  /// Применяет сохранённую геометрию и показывает окно.
  /// null — открыть с размером по умолчанию.
  Future<void> restore(WindowGeometry? geometry);

  /// Текущая геометрия окна.
  Future<WindowGeometry?> current();

  /// Начало перетаскивания окна за содержимое.
  ///
  /// Системной полосы заголовка у окна нет, и хвататься не за что: полосу
  /// рисует шелл, а нажатие на ней передаёт сюда. Зовётся один раз, в начале
  /// жеста, — дальше окно ведёт система.
  Future<void> startDrag();

  /// Развернуть на весь экран или вернуть прежний размер — то, что делало
  /// двойное нажатие на системной полосе.
  Future<void> toggleMaximized();

  /// Подписка на перемещение, изменение размера и разворот окна.
  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  void dispose();
}

/// Заглушка для тестов и платформ без управления окном.
class NoopWindowService implements WindowService {
  const NoopWindowService();

  @override
  Future<void> restore(WindowGeometry? geometry) async {}

  @override
  Future<WindowGeometry?> current() async => null;

  @override
  Future<void> startDrag() async {}

  @override
  Future<void> toggleMaximized() async {}

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}

  @override
  void dispose() {}
}
