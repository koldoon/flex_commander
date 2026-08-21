import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
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
  /// Коротко, потому что подпись живёт на кнопке в ряду: рядом такие же
  /// сжатые `Mk Dir` и `Line Num`, а длинное слово там обрезается. Полное
  /// название — в заголовке окна, места там хватает.
  ///
  /// «Адрес», а не «путь»: вводят и `ssh://user@host/srv`, и `~/Downloads`.
  String get label => 'Address';

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

  /// Идёт открытие: подключение к источнику, разбор пути, чтение каталога.
  ///
  /// Пока идёт, подтверждать нечего (`Open` приглушён), а `Esc` означает
  /// «прервать» — см. [dismiss].
  @override
  bool get isRunning => _running;
  bool _running = false;

  /// Работу прервал пользователь.
  ///
  /// Отличать это от неудачи обязательно: после отмены в окне не должно
  /// появиться ни «Not found», ни чего-либо ещё — человек получил ровно то,
  /// о чём просил.
  bool _canceled = false;

  /// Чем панель занята прямо сейчас; null — работа не идёт.
  ///
  /// Это её собственная веха — «Connecting to ssh://shark…», «Reading a.zip…»:
  /// та самая строка, что в обычное время видна в строке состояния панели. Её
  /// закрывает затенение этого окна, поэтому окно показывает веху у себя.
  /// Второго канала для этого не заводится: две истины об одном и том же
  /// разошлись бы.
  String? get statusMessage => _statusMessage;
  String? _statusMessage;

  @override
  Future<void> execute() async {
    final path = (param<String>(pathParam) ?? '').trim();
    if (path.isEmpty) {
      return;
    }

    _canceled = false;
    _running = true;
    // Подписка ставится до вызова: первую веху панель выставляет синхронно,
    // ещё внутри `openPath`, и подписавшийся после неё бы её не услышал.
    panel.addListener(_onPanelChanged);
    notifyListeners();

    try {
      final opened = await panel.openPath(path);

      // Об отмене спрашиваем первым делом. Прерванное чтение каталога
      // оставляет панель там, где она была, а `openPath` отвечает при этом
      // «получилось»: закрыть по такому ответу окно значило бы сделать вид,
      // что путь открылся.
      if (_canceled) {
        return;
      }
      if (!opened) {
        // Причину берём у панели: «путь не найден» и «такой протокол мы не
        // умеем» — разные ответы, и второй сам себя объясняет.
        throw panel.error ?? FsError(path, FsErrorKind.notFound);
      }

      // Панель, в которую открыли путь, становится активной: пользователь
      // смотрит туда, куда только что пришёл.
      context.app.activate(panel);
    } finally {
      panel.removeListener(_onPanelChanged);
      _running = false;
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// Веха панели — в окно.
  ///
  /// Частоту здесь не ограничивают: панель шлёт свои вехи не чаще, чем имеет
  /// смысл перерисовывать, — у неё для этого свой `Throttle`.
  void _onPanelChanged() {
    final message = panel.busy ? panel.statusText : null;
    if (message == _statusMessage) {
      return;
    }
    _statusMessage = message;
    notifyListeners();
  }

  /// `Enter` и «Open»: выполнить и закрыть окно — кроме двух случаев.
  ///
  /// Неудача оставляет окно с сообщением: адрес правится тут же, а не
  /// набирается заново из-за одной опечатки. Отмена оставляет его молча —
  /// прерывают, чтобы поправить набранное или не ждать недоступный сервер,
  /// а уйти можно вторым `Esc`.
  @override
  Future<void> submit() async {
    if (_running) {
      return;
    }
    error = null;

    try {
      await execute();
    } on FsError catch (failure) {
      error = failure.message;
      return;
    }

    if (_canceled) {
      return;
    }
    closeDialog();
  }

  /// `Esc` и «Cancel»: во время работы — прервать, в остальное время — закрыть.
  ///
  /// Отмена жёсткая, без вопроса «точно прервать?»: спрашивать стоит там, где
  /// сделанное необратимо (копирование посреди дерева), а подключение и чтение
  /// бросают, ничего не испортив.
  @override
  void dismiss() {
    if (_running) {
      _canceled = true;
      panel.cancel();
      return;
    }
    super.dismiss();
  }

  /// Что показать в поле, когда окно открылось.
  ///
  /// Показанный путь, а не машинный: человек правит то, что видит в заголовке
  /// панели, и `/home/a.zip:zip:/inner` там ни к чему. Разобрать такую строку
  /// обратно умеет `ProviderRegistry.resolveDisplayPath`.
  String get currentPath => panel.directory?.displayPath ?? '';

  @override
  Widget? getDialog(BuildContext context) {
    return ListenableBuilder(listenable: this, builder: (context, _) => _OpenPathForm(command: this));
  }
}

/// Одно поле — путь, строка о ходе работы и две кнопки.
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
    final command = widget.command;

    return CommandDialogForm(
      // Неудача не закрывает окно: путь правится тут же и пробуется снова.
      error: command.error,
      // Работа уже идёт — подтверждать нечего.
      busy: command.isRunning,
      onCancel: command.dismiss,
      onSubmit: command.submit,
      submitLabel: 'Open',
      children: [
        CommandDialogField(
          label: 'Path',
          child: FcTextField(
            controller: _path,
            autofocus: true,
            // Поле остаётся живым и во время работы: выключенное отдало бы
            // фокус, а вернуть его после отмены было бы нечем — `autofocus`
            // срабатывает один раз. Набранное при этом никому не мешает:
            // параметр читается на входе в `execute`.
            hintText: '/etc or ssh://user@host/srv',
            onChanged: (value) => command.setParam(OpenPathCommand.pathParam, value),
            onSubmitted: (_) => command.submit(),
          ),
        ),
        // Чем занята панель прямо сейчас. Без этой строки открытие адреса через
        // сервер и два архива выглядит зависшим приложением: сказать о ходе
        // работы есть что, но говорится это в строке состояния панели — под
        // затенением этого самого окна.
        if (command.statusMessage case final message?)
          CommandDialogField(
            label: 'Status',
            // Одной строкой: адреса длинные, а окно не должно расти вниз на
            // каждой вехе.
            child: Text(
              message,
              style: FcTheme.of(context).dialogTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
