import 'package:flutter/widgets.dart';

import '../../model/app/panel.dart';
import '../../model/panel/sort_spec.dart';
import '../../model/settings/app_settings.dart';
import '../../view/dialogs/help_table.dart';
import '../../view/panel/file_table_header.dart';
import 'app_command.dart';
import 'command_registry.dart';

/// Справка: что сейчас настроено и какие клавиши за что отвечают.
///
/// Первый шаг сознательно скромный — таблица текущего состояния вместо
/// рассказа о том, как чем пользоваться. Она полезна сразу: настройки лежат
/// в файле, привязки клавиш нигде не показаны, а спросить об этом до сих пор
/// было негде.
class HelpCommand extends AppCommand {
  HelpCommand({CommandRegistry? Function()? registry}) : _registry = registry;

  /// Реестр — способом его спросить, а не самим реестром: справка живёт
  /// внутри него же, и к моменту создания команды его ещё нет.
  final CommandRegistry? Function()? _registry;

  @override
  String get id => 'app.help';

  @override
  String get label => 'Help';

  @override
  bool get hasDialog => true;

  /// Фокус берёт сама таблица: её листают клавишами.
  @override
  bool get dialogTakesFocus => true;

  @override
  bool isExecutable(CommandContext context) => true;

  /// Показать — это и есть вся работа: окно рисует справку, делать больше
  /// нечего. Enter в нём поэтому равносилен «закрыть».
  @override
  Future<void> execute() async {}

  @override
  Widget? getDialog(BuildContext context) => CommandDialogHelp(sections: _sections(), onClose: dismiss);

  List<HelpSection> _sections() => [_settings(), _keys()];

  /// Настройки — то, что приложение помнит между запусками.
  HelpSection _settings() {
    final app = context.app;
    final settings = app.settings;

    return HelpSection('Settings', [
      HelpRow('Left panel', _pathOf(app.left)),
      HelpRow('Right panel', _pathOf(app.right)),
      HelpRow('Active panel', identical(app.activePanel, app.left) ? 'Left' : 'Right'),
      HelpRow('Split', '${(settings.splitRatio * 100).round()}% left'),
      HelpRow('Hidden files', _bothPanels(settings, (panel) => panel.showHidden ? 'shown' : 'hidden')),
      HelpRow('Sort', _bothPanels(settings, (panel) => _sortOf(panel.sort))),
      HelpRow('Columns', _bothPanels(settings, _columnsOf)),
      HelpRow('Directory scans', '${settings.sizeScanConcurrency} at a time'),
      HelpRow('Window', _windowOf(settings)),
    ]);
  }

  /// Клавиши — в порядке приоритета, том же, в котором их разбирает реестр.
  HelpSection _keys() {
    final registry = _registry?.call();
    if (registry == null) {
      return const HelpSection('Keys', [HelpRow('', 'Key bindings are not available')]);
    }

    return HelpSection('Keys', [
      for (final binding in registry.bindings)
        HelpRow(binding.keys.toString(), registry.find(binding.commandId)?.label ?? binding.commandId),
    ]);
  }

  String _pathOf(Panel panel) => panel.directory?.displayPath ?? '—';

  /// Настройка у каждой панели своя, и различие важнее общего вида: показываем
  /// обе, а совпадающие значения не удваиваем.
  String _bothPanels(AppSettings settings, String Function(PanelSettings panel) valueOf) {
    final left = valueOf(settings.left);
    final right = valueOf(settings.right);
    return left == right ? left : 'left — $left, right — $right';
  }

  String _sortOf(SortSpec sort) {
    final direction = sort.direction == SortDirection.ascending ? '↑' : '↓';
    return '${FileTableHeaderCell.titleOf(sort.column)} $direction';
  }

  String _columnsOf(PanelSettings panel) => panel.columns.visibleColumns
      .where((column) => FileTableHeaderCell.titleOf(column.id).isNotEmpty)
      .map((column) => FileTableHeaderCell.titleOf(column.id))
      .join(', ');

  String _windowOf(AppSettings settings) {
    final window = settings.window;
    if (window == null) {
      return 'not saved yet';
    }
    final size = '${window.width.round()}×${window.height.round()}';
    return window.maximized ? '$size, maximized' : '$size at ${window.left.round()}, ${window.top.round()}';
  }
}
