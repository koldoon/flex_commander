import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../model/app/application.dart';
import '../model/os/window_service.dart';
import '../model/settings/app_settings.dart';
import '../model/settings/settings_store.dart';
import '../model/settings/window_geometry.dart';
import 'commands/command_registry.dart';
import 'commands/default_commands.dart';
import 'panel_controller.dart';

/// Состояние приложения — реализация [Application].
///
/// Ветвление «если активна левая, то…» живёт только здесь: панели друг о друге
/// не знают. Активная панель — источник операции, пассивная — её приёмник.
/// Команды видят приложение только как [Application].
class AppController extends ChangeNotifier implements Application {
  AppController({
    required this.left,
    required this.right,
    required this.store,
    required AppSettings settings,
    CommandRegistry? commands,
    WindowService? window,
    this.saveDelay = const Duration(seconds: 1),
  }) : _splitRatio = settings.splitRatio,
       _windowGeometry = settings.window,
       _initialSettings = settings,
       window = window ?? const NoopWindowService(),
       commands = commands ?? defaultCommandRegistry() {
    // Одна панель активна всегда, ещё до первого чтения каталогов.
    left.setActive(settings.activePanel != 1);
    right.setActive(settings.activePanel == 1);
    left.addListener(_onPanelChanged);
    right.addListener(_onPanelChanged);
    this.window.addListener(_onWindowChanged);
    this.commands.attach(this);
  }

  /// Тип уточнён до реализации: виджетам нужна подписка на изменения,
  /// командам — только интерфейс [Panel].
  @override
  final PanelController left;

  @override
  final PanelController right;
  final SettingsStore store;

  /// Действия приложения: за кнопкой нижней панели и за горячей клавишей
  /// стоит одна и та же команда.
  final CommandRegistry commands;

  /// Окно приложения. Без управления окном (в тестах) — заглушка.
  final WindowService window;

  /// Задержка перед записью настроек. Настройки пишутся и при выходе, но
  /// отложенная запись бережёт их и при аварийном завершении.
  final Duration saveDelay;

  final AppSettings _initialSettings;

  double _splitRatio;
  WindowGeometry? _windowGeometry;
  Timer? _saveTimer;
  String? _savedSnapshot;

  /// Активная панель: в ней курсор и ввод с клавиатуры.
  @override
  PanelController get activePanel => left.active ? left : right;

  /// Пассивная панель — приёмник операций копирования и перемещения.
  @override
  PanelController get passivePanel => left.active ? right : left;

  /// Доля ширины окна под левой панелью.
  @override
  double get splitRatio => _splitRatio;

  /// Последняя известная геометрия окна.
  @override
  WindowGeometry? get windowGeometry => _windowGeometry;

  /// Запоминает геометрию окна.
  ///
  /// У развёрнутого окна размеры совпадают с экраном, поэтому запоминается не
  /// они, а те, к которым окно вернётся после сворачивания — иначе оно так и
  /// осталось бы во весь экран.
  void setWindowGeometry(WindowGeometry? geometry) {
    if (geometry == null) {
      return;
    }
    final previous = _windowGeometry;
    final updated = geometry.maximized && previous != null ? previous.copyWith(maximized: true) : geometry;

    if (_windowGeometry == updated) {
      return;
    }
    _windowGeometry = updated;
    _scheduleSave();
  }

  @override
  void activate(Panel panel) {
    assert(panel == left || panel == right, 'Панель не принадлежит этому приложению');
    if (panel.active) {
      return;
    }
    left.setActive(panel == left);
    right.setActive(panel == right);
    notifyListeners();
  }

  /// Переключить активную панель (Tab).
  @override
  void toggleActivePanel() => activate(left.active ? right : left);

  /// Окна команд держит реестр — он же их и создаёт.
  @override
  void closeDialog(String runId) => commands.closeDialog(runId);

  @override
  void setSplitRatio(double value) {
    final clamped = value.clamp(AppSettings.minSplitRatio, AppSettings.maxSplitRatio);
    if (_splitRatio == clamped) {
      return;
    }
    _splitRatio = clamped;
    notifyListeners();
    _scheduleSave();
  }

  /// Открывает сохранённые каталоги и активирует панель, которая была активной
  /// в прошлый раз. Недоступный путь заменяется корнем провайдера, чтобы
  /// приложение всегда стартовало в рабочем состоянии.
  @override
  Future<void> start() async {
    _savedSnapshot = _snapshot();
    await window.restore(_initialSettings.window);

    await Future.wait([_openPanel(left, _initialSettings.left.path), _openPanel(right, _initialSettings.right.path)]);

    activate(_initialSettings.activePanel == 1 ? right : left);
    // Первый кадр показывается уже с восстановленным состоянием, поэтому
    // отложенную запись, вызванную открытием каталогов, отменяем.
    _saveTimer?.cancel();
    _savedSnapshot = _snapshot();
  }

  /// Сохраняет настройки и останавливает незавершённые операции.
  @override
  Future<void> shutdown() async {
    _saveTimer?.cancel();
    left.cancel();
    right.cancel();
    await commands.shutdown();
    // Геометрию здесь не спрашиваем: выход происходит внутри системного
    // обработчика завершения, и обращение к плагину через платформенный канал
    // в этот момент приводит к взаимной блокировке — приложение перестаёт
    // закрываться. Сохраняется последнее известное состояние, а обновляет его
    // captureWindowGeometry.
    await save();
  }

  /// Текущее состояние приложения в виде сохраняемых настроек.
  @override
  AppSettings get settings => AppSettings(
    left: left.settings,
    right: right.settings,
    activePanel: left.active ? 0 : 1,
    splitRatio: _splitRatio,
    window: _windowGeometry,
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
  /// Спрашивает у окна его текущую геометрию и запоминает её.
  ///
  /// Вызывается на изменения окна и при уходе приложения на второй план —
  /// то есть заведомо не в момент завершения процесса.
  Future<void> captureWindowGeometry() async {
    setWindowGeometry(await window.current());
  }

  void _onWindowChanged() => unawaited(captureWindowGeometry());

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
    window.removeListener(_onWindowChanged);
    super.dispose();
  }
}
