import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

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

  static const String commandId = 'app.help';

  @override
  String get id => commandId;

  @override
  String get label => tr('Help');

  /// В справке лежит перечень клавиш — по нему её и ищут.
  @override
  Set<String> get keywords => const {'keys', 'shortcuts', 'keyboard', 'bindings'};

  /// В заголовке места больше, чем на кнопке в ряду.
  String get dialogTitle => 'Help';

  @override
  bool isExecutable(CommandContext context) => true;

  /// Показать — это и есть вся работа.
  ///
  /// Окно команда не держит: показала и ушла. Состояния прогона у справки нет
  /// вовсе — таблица собирается один раз и дальше только листается, — поэтому
  /// экземпляр команды после запуска не нужен ни для чего.
  ///
  /// Enter в таком окне равносилен «закрыть»: делать в нём больше нечего.
  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        title: dialogTitle,
        takesFocus: true,
        content: FcKeyValueTable(sections: _sections(context), onClose: close),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }

  List<FcTableSection> _sections(CommandContext context) => [_settings(context), ..._commands(context)];

  /// Настройки — то, что приложение помнит между запусками.
  FcTableSection _settings(CommandContext context) {
    final app = context.app;

    return FcTableSection(tr('Settings'), [
      FcTableRow(tr('Left panel'), _pathOf(app.left)),
      FcTableRow(tr('Right panel'), _pathOf(app.right)),
      FcTableRow(tr('Active panel'), identical(app.activePanel, app.left) ? tr('Left') : tr('Right')),
      FcTableRow(tr('Split'), tr('{percent}% left', args: {'percent': (app.splitRatio * 100).round()})),
      FcTableRow(tr('Hidden files'), _bothPanels(app, (panel) => panel.showHidden ? tr('shown') : tr('hidden'))),
      FcTableRow(tr('Sort'), _bothPanels(app, (panel) => _sortOf(panel.sort))),
      FcTableRow(tr('Columns'), _bothPanels(app, _columnsOf)),
      FcTableRow(tr('Directory scans'), tr('{count} at a time', args: {'count': app.sizeScanConcurrency})),
      FcTableRow(tr('Window'), _windowOf(app.windowGeometry)),
    ]);
  }

  /// Команды: что умеет приложение, какими клавишами и что это значит.
  ///
  /// Список берётся у реестра, а не пишется здесь: новая команда или новая
  /// привязка появляется в справке сама, и разойтись с действительностью она
  /// не может.
  /// Команды — по модулям, в порядке их установки.
  ///
  /// Группировка не украшение: команд уже под полсотни, и одним списком в них
  /// не найтись. Модуль — единственное деление, которое приложение знает само
  /// (и то, по которому возможности включаются и выключаются), поэтому и
  /// заголовки берутся оттуда: «Terminal», «File operations». Придумывать своё
  /// деление — значит держать его в согласии руками.
  ///
  /// Порядок — тот же, в каком модули объявлены: он не случаен, им задаётся
  /// приоритет привязок.
  List<FcTableSection> _commands(CommandContext context) {
    final registry = _registry?.call();
    if (registry == null) {
      return [
        FcTableSection(tr('Commands'), [FcTableRow('', tr('Command list is not available'))]),
      ];
    }

    final grouped = <String, List<FcTableRow>>{};
    for (final command in registry.installed) {
      final owner = registry.ownerOf(command.id);
      // Пустое — команда пришла не модулем: в приложении такого нет, а в
      // тесте бывает. Своя строка лучше, чем пропажа.
      // Название модуля приходит английским — переводит его тот, кто
      // показывает: у модуля служб нет.
      final title = owner.isEmpty ? tr('Other') : tr(owner);
      grouped
          .putIfAbsent(title, () => [])
          .add(FcTableRow(command.label, _keysOf(registry, command.id), command.description));
    }

    // Порядок — по объявлению модулей, а не по появлению команд: модуль,
    // занявший место чужой заглушки (просмотрщик встаёт на `F3` оболочки),
    // иначе всплывал бы наверх.
    return [
      for (final title in [for (final owner in registry.owners) tr(owner), tr('Other')])
        if (grouped[title] case final rows?) FcTableSection(title, rows),
    ];
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

  String _pathOf(Session panel) => panel.currentPath.isEmpty ? '—' : panel.currentPath;

  /// Настройка у каждой панели своя, и различие важнее общего вида: показываем
  /// обе, а совпадающие значения не удваиваем.
  String _bothPanels(Application app, String Function(Session panel) valueOf) {
    final left = valueOf(app.left);
    final right = valueOf(app.right);
    return left == right ? left : 'left — $left, right — $right';
  }

  String _sortOf(SortSpec sort) {
    final direction = sort.direction == SortDirection.ascending ? '↑' : '↓';
    return '${sort.column.title} $direction';
  }

  String _columnsOf(Session panel) => panel.columns.visibleColumns
      .where((column) => column.id.title.isNotEmpty)
      .map((column) => column.id.title)
      .join(', ');

  String _windowOf(WindowGeometry? window) {
    if (window == null) {
      return 'not saved yet';
    }
    final size = '${window.width.round()}×${window.height.round()}';
    return window.maximized ? '$size, maximized' : '$size at ${window.left.round()}, ${window.top.round()}';
  }
}
