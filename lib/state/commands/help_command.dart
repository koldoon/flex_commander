import 'package:flutter/widgets.dart';

import '../../model/app/panel.dart';
import '../../model/panel/sort_spec.dart';
import '../../model/settings/app_settings.dart';
import '../../view/dialogs/help_table.dart';
import '../../view/panel/file_table_header.dart';
import 'app_command.dart';
import 'command_registry.dart';
import 'key_combination.dart';

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

  List<HelpSection> _sections() => [_settings(), _commands()];

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

  /// Команды: что умеет приложение, какими клавишами и что это значит.
  ///
  /// Список берётся у реестра, а не пишется здесь: новая команда или новая
  /// привязка появляется в справке сама, и разойтись с действительностью она
  /// не может.
  HelpSection _commands() {
    final registry = _registry?.call();
    if (registry == null) {
      return const HelpSection('Commands', [HelpRow('', 'Command list is not available')]);
    }

    return HelpSection('Commands', [
      for (final command in registry.installed)
        HelpRow(command.label, _keysOf(registry, command.id), command.description),
    ]);
  }

  /// Клавиши команды — все, через запятую, в порядке приоритета.
  ///
  /// У команды их бывает несколько: на macOS F-клавиши заняты системой, и
  /// рядом с ними стоят привычные сочетания.
  String _keysOf(CommandRegistry registry, String commandId) {
    final keys = [
      for (final binding in registry.bindingsOf(commandId))
        binding.keys == KeyCombination.anyCharacter ? 'any letter' : binding.keys.toString(),
    ];
    // Команда без привязки — не ошибка: её вызывают из списка команд.
    return keys.isEmpty ? '—' : keys.join(', ');
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
