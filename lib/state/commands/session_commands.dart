import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Команды открытых сессий (`docs/spec/panel-sessions.md`, §9).
///
/// Все они про **активную панель**: набор заводят и показывают там, где
/// работают. Соседняя сторона живёт своим показанным набором и о заведённом
/// здесь не узнаёт.
///
/// Сторона берётся у рабочей области, а не у сессии: под наложением — быстрым
/// просмотром, просмотрщиком — панели не видно, и наборы там ни при чём.
ViewportPosition? _sideOf(CommandContext context) => context.app.view.positionOf(context.session);

/// Набор, показанный в активной панели; null — панели не видно.
Panel? _panelOf(CommandContext context) {
  final side = _sideOf(context);
  return side == null ? null : context.app.panelAt(side);
}

/// Имя набора для человека: данное рукой, а иначе — каталог показанной сессии.
///
/// Совпавшие разводятся именем родителя (`src — lib`), как это делают
/// редакторы; остальные остаются короткими (`docs/spec/panel-sessions.md`, §8).
String panelTitle(Panel panel, List<Panel> among) {
  final name = _nameOf(panel);
  final twins = among.where((other) => !identical(other, panel) && _nameOf(other) == name);
  if (twins.isEmpty) {
    return name;
  }
  final parent = _parentOf(panel);
  return parent.isEmpty ? name : '$name — $parent';
}

String _nameOf(Panel panel) {
  if (panel.name.isNotEmpty) {
    return panel.name;
  }
  final session = panel.session;
  final header = session.headerText;
  if (header != null && header.isNotEmpty) {
    return header;
  }
  final name = session.directoryName;
  return name.isEmpty ? (session.currentPath.isEmpty ? '/' : session.currentPath) : name;
}

String _parentOf(Panel panel) {
  final path = panel.session.currentPath;
  final at = path.lastIndexOf('/');
  if (at <= 0) {
    return '';
  }
  final parent = path.substring(0, at);
  final from = parent.lastIndexOf('/');
  return from < 0 ? parent : parent.substring(from + 1);
}

/// Новый набор на текущем каталоге — и сразу показать его здесь.
class NewSessionCommand extends AppCommand {
  static const String commandId = 'panel.sessions.new';

  @override
  String get id => commandId;

  @override
  String get label => tr('New session');

  @override
  String get description => tr('Open one more session on the current directory');

  @override
  Set<String> get keywords => const {'panel', 'tab', 'duplicate'};

  @override
  bool isExecutable(CommandContext context) => _sideOf(context) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    if (side == null) {
      return;
    }
    await context.app.openPanel(side, like: context.session);
  }
}

/// Закрыть набор, показанный здесь.
///
/// Закрыть можно любой, в том числе последний: панель без набора не бывает, и
/// на его место встаёт новый (`docs/spec/panel-sessions.md`, §7).
class CloseSessionCommand extends AppCommand {
  static const String commandId = 'panel.sessions.close';

  @override
  String get id => commandId;

  @override
  String get label => tr('Close session');

  @override
  String get description => tr('Close the session shown here and let its source go');

  @override
  Set<String> get keywords => const {'panel', 'tab'};

  @override
  bool isExecutable(CommandContext context) => _panelOf(context) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = _panelOf(context);
    if (panel != null) {
      context.app.closePanel(panel);
    }
  }
}

/// Соседний набор — по кругу.
class CycleSessionsCommand extends AppCommand {
  CycleSessionsCommand({required this.forward});

  static const String nextId = 'panel.sessions.next';
  static const String previousId = 'panel.sessions.previous';

  final bool forward;

  @override
  String get id => forward ? nextId : previousId;

  @override
  String get label => forward ? tr('Next session') : tr('Previous session');

  @override
  String get description => tr('Show the neighbouring session here');

  @override
  Set<String> get keywords => const {'switch', 'cycle', 'tab'};

  @override
  bool isExecutable(CommandContext context) => _sideOf(context) != null && context.app.panels.length > 1;

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    final panel = _panelOf(context);
    if (side == null || panel == null) {
      return;
    }
    final panels = context.app.panels;
    final at = panels.indexOf(panel);
    if (at < 0) {
      return;
    }
    // По кругу: список короткий, и упираться в его край незачем.
    context.app.showPanel(side, panels[(at + (forward ? 1 : -1) + panels.length) % panels.length]);
  }
}

/// Набор по номеру: `Alt-1`…`Alt-9`.
class SelectSessionCommand extends AppCommand {
  static const String commandId = 'panel.sessions.select';

  /// Номер набора, считая с единицы.
  static const String numberParam = 'number';

  @override
  String get id => commandId;

  @override
  String get label => tr('Session by number');

  @override
  String get description => tr('Show the session with this number here');

  @override
  Set<String> get keywords => const {'switch', 'tab'};

  static int _numberOf(CommandContext context) =>
      int.tryParse(context.invocation.param<String>(numberParam) ?? '') ?? 0;

  @override
  bool isExecutable(CommandContext context) {
    if (_sideOf(context) == null) {
      return false;
    }
    final number = _numberOf(context);
    // Клавиша с номером, которому набора нет, ничего не делает — и не мешает
    // тому, кто объявлен следом.
    return number >= 1 && number <= context.app.panels.length;
  }

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    final number = _numberOf(context);
    final panels = context.app.panels;
    if (side == null || number < 1 || number > panels.length) {
      return;
    }
    context.app.showPanel(side, panels[number - 1]);
  }
}

/// Окно выбора набора: все открытые списком, с нечётким отбором.
///
/// Устроено палитрой, а не своим окном: вопрос тот же — «найди по названию и
/// покажи», — и повторять его вторым виджетом незачем
/// (`docs/spec/panel-sessions.md`, §3).
class ChooseSessionCommand extends AppCommand {
  static const String commandId = 'panel.sessions.choose';

  @override
  String get id => commandId;

  @override
  String get label => tr('Sessions');

  @override
  String get description => tr('All open sessions; show the chosen one here');

  @override
  Set<String> get keywords => const {'switch', 'tab', 'panel', 'list'};

  @override
  bool isExecutable(CommandContext context) => _sideOf(context) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final side = _sideOf(context);
    if (side == null) {
      return;
    }
    final app = context.app;
    final panels = app.panels;
    final view = app.view;

    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    dialogId = view.showDialog(
      DialogSpec(
        takesFocus: true,
        ownWidth: true,
        content: FcCommandPalette(
          items: [
            for (var at = 0; at < panels.length; at++)
              PaletteItem(
                id: '$at',
                label: panelTitle(panels[at], panels),
                // Путь — под названием: имена короткие и повторяются, а
                // отличает наборы именно место.
                description: panels[at].session.currentPath,
                owner: '',
                // Номерная клавиша — у первых девяти: увидел раз, дальше
                // жмёшь её.
                keys: at < 9 ? 'Alt-${at + 1}' : '',
              ),
          ],
          recent: const [],
          onRun: (chosen) {
            close();
            final at = int.tryParse(chosen) ?? -1;
            if (at >= 0 && at < panels.length) {
              app.showPanel(side, panels[at]);
            }
          },
        ),
        onDismiss: close,
      ),
    );
  }
}

/// Назвать набор своим именем.
///
/// Названный не переименовывается вслед за каталогом: имя дано набору, а не
/// месту (`docs/spec/panel-sessions.md`, §8). Пустое имя возвращает набор к
/// имени каталога.
class RenameSessionCommand extends AppCommand {
  static const String commandId = 'panel.sessions.rename';

  /// Новое имя — из привязки или сценария; окно тогда не показывается.
  static const String nameParam = 'name';

  @override
  String get id => commandId;

  @override
  String get label => tr('Rename session');

  @override
  String get description => tr('Give this session a name of your own');

  @override
  Set<String> get keywords => const {'tab', 'panel', 'title'};

  @override
  bool isExecutable(CommandContext context) => _panelOf(context) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final panel = _panelOf(context);
    if (panel == null) {
      return;
    }

    final given = context.invocation.param<String>(nameParam);
    if (given != null) {
      context.app.renamePanel(panel, given.trim());
      return;
    }

    final view = context.app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);

    final state = _RenameSessionState(
      // Не имя каталога: подставленное имя выглядело бы как данное рукой, а
      // подтвердить его значило бы отвязать набор от каталога молча.
      original: panel.name,
      rename: (name) => context.app.renamePanel(panel, name),
      close: close,
    );

    dialogId = view.showDialog(
      DialogSpec(
        title: tr('Rename session'),
        takesFocus: true,
        content: _RenameSessionForm(state: state),
        onSubmit: state.submit,
        onDismiss: close,
      ),
    );
  }
}

/// Что набрано в окне названия набора.
class _RenameSessionState {
  _RenameSessionState({required this.original, required this.rename, required this.close}) : name = original;

  final String original;
  final void Function(String name) rename;
  final VoidCallback close;

  String name;

  void submit() {
    rename(name.trim());
    close();
  }
}

/// Поле с именем набора — и подсказкой о том, что даёт пустое.
class _RenameSessionForm extends StatefulWidget {
  const _RenameSessionForm({required this.state});

  final _RenameSessionState state;

  @override
  State<_RenameSessionForm> createState() => _RenameSessionFormState();
}

class _RenameSessionFormState extends State<_RenameSessionForm> {
  late final TextEditingController _name = TextEditingController(text: widget.state.original)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.state.original.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return CommandDialogForm(
      onCancel: state.close,
      onSubmit: state.submit,
      submitLabel: context.strings.tr('Rename'),
      children: [
        CommandDialogField.wide(
          child: FcTextField(
            controller: _name,
            autofocus: true,
            hintText: context.strings.tr('Empty name follows the directory'),
            onChanged: (value) => state.name = value,
            onSubmitted: (_) => state.submit(),
          ),
        ),
      ],
    );
  }
}
