import 'package:fc_api/fc_api.dart';
import 'package:flutter/widgets.dart';

/// Открыть в панели произвольный путь — включая адрес чужого источника.
///
/// То же, чем в Norton Commander был выбор диска для панели, только вместо
/// букв дисков строка целиком: `/etc`, `~/Downloads`, а со временем и
/// `ssh://user@host/srv`. На macOS дисков в том смысле нет вовсе, а источников
/// будет много — значит, спрашивать надо адрес, а не букву.
///
/// **Команда работает с названной панелью, а не с активной.** Это единственное
/// такое место в приложении, и оно того стоит: `Cmd+F1` — всегда про левую,
/// куда бы ни смотрел курсор. Какая именно панель, приходит параметром
/// привязки, а не отдельной командой на каждую: обе клавиши делают одно и то
/// же.
class OpenPathCommand extends AppCommand {
  static const String commandId = 'panel.openPath';

  /// Значение параметра [panelParam]: левая или правая.
  static const String panelParam = 'panel';
  static const String leftPanel = 'left';
  static const String rightPanel = 'right';

  /// Введённый путь — окно кладёт его сюда по мере набора.
  static const String pathParam = 'path';

  @override
  String get id => commandId;

  @override
  String get label => 'Open path';

  @override
  String get description => 'Open any path or address in the left or right panel';

  /// Панель, о которой идёт речь.
  Panel get panel => _isLeft ? context.app.left : context.app.right;

  bool get _isLeft => param<String>(panelParam) != rightPanel;

  @override
  String get dialogTitle => 'Open path (${_isLeft ? 'left' : 'right'} panel)';

  @override
  bool get hasDialog => true;

  @override
  bool get dialogTakesFocus => true;

  /// Окно встаёт над своей панелью.
  ///
  /// Иначе «открыть путь в левой» и «открыть путь в правой» неотличимы на вид:
  /// заголовок читают не в первую очередь. Левая панель занимает долю
  /// `splitRatio` — её середина приходится на половину этой доли; правая
  /// начинается там же и тянется до края.
  @override
  DialogArea get dialogArea {
    final ratio = context.app.splitRatio;
    return _isLeft ? DialogArea(end: ratio) : DialogArea(start: ratio);
  }

  @override
  bool isExecutable(CommandContext context) {
    // Панель, занятая чтением, нового пути не примет: сперва пусть закончит.
    final target = param<String>(panelParam) == rightPanel ? context.app.right : context.app.left;
    return !target.busy;
  }

  @override
  Future<void> execute() async {
    final path = (param<String>(pathParam) ?? '').trim();
    if (path.isEmpty) {
      return;
    }

    // Панель, в которую открыли путь, становится активной: пользователь смотрит
    // туда, куда только что пришёл.
    if (!await panel.openPath(path)) {
      // Причину берём у панели: «путь не найден» и «такой протокол мы не
      // умеем» — разные ответы, и второй сам себя объясняет.
      throw panel.error ?? FsError(path, FsErrorKind.notFound);
    }
    context.app.activate(panel);
  }

  /// Что показать в поле, когда окно открылось.
  String get currentPath => panel.directory?.pathString ?? '';

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(listenable: this, builder: (context, _) => _OpenPathForm(command: this));
  }
}

/// Одно поле — путь, и две кнопки.
class _OpenPathForm extends StatefulWidget {
  const _OpenPathForm({required this.command});

  final OpenPathCommand command;

  @override
  State<_OpenPathForm> createState() => _OpenPathFormState();
}

class _OpenPathFormState extends State<_OpenPathForm> {
  late final TextEditingController _path = TextEditingController(text: widget.command.currentPath)
    // Текущий путь выделен целиком: чаще его заменяют, чем правят, а если
    // правят — достаточно нажать стрелку.
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.command.currentPath.length);

  @override
  void initState() {
    super.initState();
    // Значение задаётся сразу, а не при подтверждении: Enter обрабатывает ядро,
    // и к моменту execute параметр уже должен быть на месте.
    widget.command.setParam(OpenPathCommand.pathParam, _path.text);
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandDialogForm(
      // Неудача не закрывает окно: путь правится тут же и пробуется снова.
      error: widget.command.error,
      onCancel: widget.command.dismiss,
      onSubmit: widget.command.submit,
      submitLabel: 'Open',
      child: CommandDialogField(
        label: 'Path',
        child: FcTextField(
          controller: _path,
          autofocus: true,
          hintText: '/etc or ssh://user@host/srv',
          onChanged: (value) => widget.command.setParam(OpenPathCommand.pathParam, value),
          onSubmitted: (_) => widget.command.submit(),
        ),
      ),
    );
  }
}
