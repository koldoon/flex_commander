import '../panel/column_spec.dart';
import '../panel/sort_spec.dart';
import 'window_geometry.dart';

/// Тема оформления. Собственный перечислимый тип, а не `ThemeMode` из Flutter:
/// слой моделей не должен зависеть от виджетов.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode byName(Object? value) {
    for (final mode in values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return system;
  }
}

/// Сохраняемые настройки одной панели.
class PanelSettings {
  const PanelSettings({
    required this.path,
    required this.columns,
    this.sort = const SortSpec(),
    this.showHidden = false,
  });

  /// Последний открытый каталог: полная строка пути, включая схему провайдера.
  final String path;

  final ColumnLayout columns;
  final SortSpec sort;
  final bool showHidden;

  PanelSettings copyWith({String? path, ColumnLayout? columns, SortSpec? sort, bool? showHidden}) => PanelSettings(
    path: path ?? this.path,
    columns: columns ?? this.columns,
    sort: sort ?? this.sort,
    showHidden: showHidden ?? this.showHidden,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'showHidden': showHidden,
    'sort': sort.toJson(),
    'columns': columns.toJson(),
  };

  factory PanelSettings.fromJson(Object? json, {String fallbackPath = ''}) {
    if (json is! Map) {
      return PanelSettings.defaults(fallbackPath);
    }
    final path = json['path'];
    final showHidden = json['showHidden'];

    return PanelSettings(
      path: path is String && path.isNotEmpty ? path : fallbackPath,
      columns: ColumnLayout.fromJson(json['columns']),
      sort: SortSpec.fromJson(json['sort']),
      showHidden: showHidden is bool ? showHidden : false,
    );
  }

  static PanelSettings defaults(String path) => PanelSettings(path: path, columns: ColumnLayout.defaults);
}

/// Сохраняемые настройки приложения.
class AppSettings {
  const AppSettings({
    required this.left,
    required this.right,
    this.activePanel = 0,
    this.splitRatio = 0.5,
    this.themeMode = AppThemeMode.system,
    this.window,
  });

  /// Версия формата файла. Увеличивается, когда старый файл перестаёт
  /// читаться напрямую и нужен перенос настроек.
  static const int version = 1;

  /// Доля ширины окна под левой панелью.
  static const double minSplitRatio = 0.2;
  static const double maxSplitRatio = 0.8;

  final PanelSettings left;
  final PanelSettings right;

  /// 0 — активна левая панель, 1 — правая.
  final int activePanel;

  final double splitRatio;
  final AppThemeMode themeMode;

  /// Положение и размер окна; null — окно ещё ни разу не открывали.
  final WindowGeometry? window;

  AppSettings copyWith({
    PanelSettings? left,
    PanelSettings? right,
    int? activePanel,
    double? splitRatio,
    AppThemeMode? themeMode,
    WindowGeometry? window,
  }) => AppSettings(
    left: left ?? this.left,
    right: right ?? this.right,
    activePanel: activePanel ?? this.activePanel,
    splitRatio: splitRatio ?? this.splitRatio,
    themeMode: themeMode ?? this.themeMode,
    window: window ?? this.window,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'activePanel': activePanel,
    'splitRatio': splitRatio,
    'themeMode': themeMode.name,
    if (window != null) 'window': window!.toJson(),
    'panels': [left.toJson(), right.toJson()],
  };

  /// Разбор устойчив к мусору: неизвестные поля игнорируются, отсутствующие
  /// берутся из умолчаний. Полностью нечитаемый файл — забота [SettingsStore].
  factory AppSettings.fromJson(Object? json, {String fallbackPath = ''}) {
    if (json is! Map) {
      return AppSettings.defaults(fallbackPath);
    }

    final panels = json['panels'];
    final left = panels is List && panels.isNotEmpty ? panels[0] : null;
    final right = panels is List && panels.length > 1 ? panels[1] : null;
    final activePanel = json['activePanel'];
    final splitRatio = json['splitRatio'];

    return AppSettings(
      left: PanelSettings.fromJson(left, fallbackPath: fallbackPath),
      right: PanelSettings.fromJson(right, fallbackPath: fallbackPath),
      activePanel: activePanel == 1 ? 1 : 0,
      splitRatio: splitRatio is num ? splitRatio.toDouble().clamp(minSplitRatio, maxSplitRatio) : 0.5,
      themeMode: AppThemeMode.byName(json['themeMode']),
      window: WindowGeometry.fromJson(json['window']),
    );
  }

  static AppSettings defaults(String path) =>
      AppSettings(left: PanelSettings.defaults(path), right: PanelSettings.defaults(path));
}
