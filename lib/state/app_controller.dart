import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../model/settings/app_settings.dart';
import '../model/settings/settings_store.dart';
import 'commands/command_registry.dart';
import 'commands/default_commands.dart';
import 'panel_controller.dart';

/// Состояние приложения: две панели, активная из них и общие настройки.
///
/// Ветвление «если активна левая, то…» живёт только здесь: панели друг о друге
/// не знают. Активная панель — источник операции, пассивная — её приёмник.
class AppController extends ChangeNotifier {
  AppController({
    required this.left,
    required this.right,
    required this.store,
    required AppSettings settings,
    CommandRegistry? commands,
    this.saveDelay = const Duration(seconds: 1),
  }) : _splitRatio = settings.splitRatio,
       _themeMode = settings.themeMode,
       _initialSettings = settings,
       commands = commands ?? defaultCommandRegistry() {
    // Одна панель активна всегда, ещё до первого чтения каталогов.
    left.setActive(settings.activePanel != 1);
    right.setActive(settings.activePanel == 1);
    left.addListener(_onPanelChanged);
    right.addListener(_onPanelChanged);
    this.commands.attach(this);
  }

  final PanelController left;
  final PanelController right;
  final SettingsStore store;

  /// Действия приложения: за кнопкой нижней панели и за горячей клавишей
  /// стоит одна и та же команда.
  final CommandRegistry commands;

  /// Задержка перед записью настроек. Настройки пишутся и при выходе, но
  /// отложенная запись бережёт их и при аварийном завершении.
  final Duration saveDelay;

  final AppSettings _initialSettings;

  double _splitRatio;
  AppThemeMode _themeMode;
  Timer? _saveTimer;
  String? _savedSnapshot;

  /// Активная панель: в ней курсор и ввод с клавиатуры.
  PanelController get activePanel => left.active ? left : right;

  /// Пассивная панель — приёмник операций копирования и перемещения.
  PanelController get passivePanel => left.active ? right : left;

  /// Доля ширины окна под левой панелью.
  double get splitRatio => _splitRatio;

  AppThemeMode get themeMode => _themeMode;

  void activate(PanelController panel) {
    assert(panel == left || panel == right, 'Панель не принадлежит этому приложению');
    if (panel.active) {
      return;
    }
    left.setActive(panel == left);
    right.setActive(panel == right);
    notifyListeners();
  }

  /// Переключить активную панель (Tab).
  void toggleActivePanel() => activate(left.active ? right : left);

  void setSplitRatio(double value) {
    final clamped = value.clamp(AppSettings.minSplitRatio, AppSettings.maxSplitRatio);
    if (_splitRatio == clamped) {
      return;
    }
    _splitRatio = clamped;
    notifyListeners();
    _scheduleSave();
  }

  void setThemeMode(AppThemeMode value) {
    if (_themeMode == value) {
      return;
    }
    _themeMode = value;
    notifyListeners();
    _scheduleSave();
  }

  /// Открывает сохранённые каталоги и активирует панель, которая была активной
  /// в прошлый раз. Недоступный путь заменяется корнем провайдера, чтобы
  /// приложение всегда стартовало в рабочем состоянии.
  Future<void> start() async {
    _savedSnapshot = _snapshot();

    await Future.wait([_openPanel(left, _initialSettings.left.path), _openPanel(right, _initialSettings.right.path)]);

    activate(_initialSettings.activePanel == 1 ? right : left);
    // Первый кадр показывается уже с восстановленным состоянием, поэтому
    // отложенную запись, вызванную открытием каталогов, отменяем.
    _saveTimer?.cancel();
    _savedSnapshot = _snapshot();
  }

  /// Сохраняет настройки и останавливает незавершённые операции.
  Future<void> shutdown() async {
    _saveTimer?.cancel();
    left.cancel();
    right.cancel();
    await commands.shutdown();
    await save();
  }

  /// Текущее состояние приложения в виде сохраняемых настроек.
  AppSettings get settings => AppSettings(
    left: left.settings,
    right: right.settings,
    activePanel: left.active ? 0 : 1,
    splitRatio: _splitRatio,
    themeMode: _themeMode,
  );

  Future<void> save() async {
    final snapshot = _snapshot();
    if (snapshot == _savedSnapshot) {
      return;
    }
    _savedSnapshot = snapshot;
    await store.save(settings);
  }

  Future<void> _openPanel(PanelController panel, String path) async {
    if (path.isNotEmpty && await panel.openPath(path)) {
      return;
    }
    if (await panel.openPath(panel.provider.homePath)) {
      return;
    }
    await panel.open(panel.provider.rootDirectory);
  }

  /// Панели уведомляют обо всём, включая движение курсора, поэтому запись
  /// планируется только при изменении того, что действительно сохраняется.
  void _onPanelChanged() {
    if (_snapshot() != _savedSnapshot) {
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(save()));
  }

  String _snapshot() => jsonEncode(settings.toJson());

  @override
  void dispose() {
    _saveTimer?.cancel();
    left.removeListener(_onPanelChanged);
    right.removeListener(_onPanelChanged);
    super.dispose();
  }
}
