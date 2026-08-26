import 'package:fc_api/fc_api.dart';
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
  String get label => 'Help';

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
    final settings = app.settings;

    return FcTableSection('Settings', [
      FcTableRow('Left panel', _pathOf(app.left)),
      FcTableRow('Right panel', _pathOf(app.right)),
      FcTableRow('Active panel', identical(app.activePanel, app.left) ? 'Left' : 'Right'),
      FcTableRow('Split', '${(settings.splitRatio * 100).round()}% left'),
      FcTableRow('Hidden files', _bothPanels(settings, (panel) => panel.showHidden ? 'shown' : 'hidden')),
      FcTableRow('Sort', _bothPanels(settings, (panel) => _sortOf(panel.sort))),
      FcTableRow('Columns', _bothPanels(settings, _columnsOf)),
      FcTableRow('Directory scans', '${settings.sizeScanConcurrency} at a time'),
      FcTableRow('Window', _windowOf(settings)),
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
      return const [
        FcTableSection('Commands', [FcTableRow('', 'Command list is not available')]),
      ];
    }

    final grouped = <String, List<FcTableRow>>{};
    for (final command in registry.installed) {
      final owner = registry.ownerOf(command.id);
      // Пустое — команда пришла не модулем: в приложении такого нет, а в
      // тесте бывает. Своя строка лучше, чем пропажа.
      final title = owner.isEmpty ? 'Other' : owner;
      grouped
          .putIfAbsent(title, () => [])
          .add(FcTableRow(command.label, _keysOf(registry, command.id), command.description));
    }

    // Порядок — по объявлению модулей, а не по появлению команд: модуль,
    // занявший место чужой заглушки (просмотрщик встаёт на `F3` оболочки),
    // иначе всплывал бы наверх.
    return [
      for (final title in [...registry.owners, 'Other'])
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
    return '${sort.column.title} $direction';
  }

  String _columnsOf(PanelSettings panel) => panel.columns.visibleColumns
      .where((column) => column.id.title.isNotEmpty)
      .map((column) => column.id.title)
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
