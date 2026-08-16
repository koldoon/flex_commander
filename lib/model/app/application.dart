import '../settings/app_settings.dart';
import '../settings/window_geometry.dart';
import 'panel.dart';

/// Приложение целиком — то, чем оперируют команды.
///
/// Аналог `IApplication` референса. Вместе с [Panel] и [PanelSelection] это и
/// есть API для написания команд: всё, что команде нужно знать о приложении,
/// описано здесь, а как это устроено внутри — её не касается.
abstract interface class Application {
  Panel get left;

  Panel get right;

  /// Активная панель — источник операции.
  Panel get activePanel;

  /// Пассивная панель — приёмник операции.
  Panel get passivePanel;

  /// Закрывает окно запущенной команды.
  ///
  /// Команда получает идентификатор запуска при создании и просит закрыть
  /// именно своё окно: одновременно могут работать несколько команд.
  void closeDialog(String runId);

  void activate(Panel panel);

  /// Переключить активную панель.
  void toggleActivePanel();

  /// Доля ширины окна под левой панелью.
  double get splitRatio;

  void setSplitRatio(double value);

  AppThemeMode get themeMode;

  void setThemeMode(AppThemeMode mode);

  /// Последняя известная геометрия окна.
  WindowGeometry? get windowGeometry;

  /// Текущее состояние приложения в виде сохраняемых настроек.
  AppSettings get settings;

  /// Запуск: восстановление окна и каталогов.
  Future<void> start();

  /// Завершение: сохранение настроек и остановка операций.
  Future<void> shutdown();
}
