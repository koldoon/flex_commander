import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'navigation_settings.dart';

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
  OpenPathCommand({required this.settings, required this.save});

  /// Раздел модуля: из него берут историю и её предел.
  ///
  /// Функцией, а не значением: раздел живёт столько же, сколько приложение, а
  /// команда пересоздаётся на каждый вызов.
  final NavigationSettings Function() settings;

  /// Попросить записать раздел на диск: история должна пережить перезапуск.
  final VoidCallback save;

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

  /// Ею же открывают сервер, поэтому `ssh` и `connect` — тоже про неё.
  @override
  Set<String> get keywords => const {'path', 'location', 'go to', 'url', 'ssh', 'connect', 'open path'};

  /// Панель, о которой идёт речь. Какая именно — известно только из вызова.
  Panel panelOf(CommandContext context) => _isLeft(context) ? context.app.left : context.app.right;

  bool _isLeft(CommandContext context) => context.invocation.param<String>(panelParam) != rightPanel;

  String titleOf(CommandContext context) => 'Open path (${_isLeft(context) ? 'left' : 'right'} panel)';

  /// Окно встаёт над своей панелью.
  ///
  /// Иначе «открыть путь в левой» и «открыть путь в правой» неотличимы на вид:
  /// заголовок читают не в первую очередь. Левая панель занимает долю
  /// `splitRatio` — её середина приходится на половину этой доли; правая
  /// начинается там же и тянется до края.
  DialogArea areaOf(CommandContext context) {
    final ratio = context.app.splitRatio;
    return _isLeft(context) ? DialogArea(end: ratio) : DialogArea(start: ratio);
  }

  @override
  bool isExecutable(CommandContext context) {
    // Панель, занятая чтением, нового пути не примет: сперва пусть закончит.
    return !panelOf(context).busy;
  }

  /// Открыть путь — или сперва спросить, какой.
  ///
  /// Путь задают либо привязкой и сценарием, либо человеком в окне. Первый
  /// случай идёт мимо окна вовсе; во втором команда показывает окно и уходит,
  /// а всё, что живёт дальше — набранное, ход работы, ошибка, — принадлежит
  /// самому окну.
  @override
  Future<void> execute(CommandContext context) async {
    final panel = panelOf(context);
    final history = settings();
    final state = OpenPathDialogState(
      panel: panel,
      activate: () => context.app.activate(panel),
      remember: (address) {
        history.remember(address);
        save();
      },
    );

    final given = (context.invocation.param<String>(pathParam) ?? '').trim();
    if (given.isNotEmpty) {
      state.path = given;
      await state.submit();
      if (state.error != null) {
        // Сценарий и привязка окна не видят: неудачу им сообщает исключение,
        // а не строка в окне, которого нет.
        throw panel.error ?? FsError(given, FsErrorKind.notFound);
      }
      return;
    }

    final view = context.app.view;
    state.path = panel.directory?.displayPath ?? '';

    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: titleOf(context),
        area: areaOf(context),
        takesFocus: true,
        content: _OpenPathForm(state: state, history: history.shownPaths),
        onSubmit: state.submit,
        onDismiss: state.dismiss,
      ),
    );
  }

  /// Что показать в поле, когда окно открылось.
  ///
  /// Показанный путь, а не машинный: человек правит то, что видит в заголовке
  /// панели, и `/home/a.zip:zip:/inner` там ни к чему. Разобрать такую строку
  /// обратно умеет `ProviderRegistry.resolveDisplayPath`.
}

/// Что набрано в окне адреса, чем занята панель и что из этого вышло.
///
/// Живёт, пока открыто окно: команда, показав его, уходит. Здесь же и отмена —
/// прерывают открытие, а не команду.
class OpenPathDialogState extends ChangeNotifier {
  OpenPathDialogState({required this.panel, required this.activate, required this.remember});

  final Panel panel;

  /// Панель, в которую открыли путь, становится активной: пользователь
  /// смотрит туда, куда только что пришёл.
  final VoidCallback activate;

  /// Записать удавшийся адрес в историю.
  ///
  /// Зовётся **после** успеха, а не при отправке: адрес с опечаткой не должен
  /// всплывать в подсказках.
  final void Function(String address) remember;

  String path = '';

  /// Идёт открытие: подключение к источнику, разбор пути, чтение каталога.
  ///
  /// Пока идёт, подтверждать нечего (`Open` приглушён), а `Esc` означает
  /// «прервать».
  bool get running => _running;
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

  String? error;

  /// Чем закрыть себя; null — окно ещё не показано (так бывает в тесте).
  VoidCallback? close;

  /// `Enter` и «Open»: открыть и закрыть окно — кроме двух случаев.
  ///
  /// Неудача оставляет окно с сообщением: адрес правится тут же, а не
  /// набирается заново из-за одной опечатки. Отмена оставляет его молча —
  /// прерывают, чтобы поправить набранное или не ждать недоступный сервер,
  /// а уйти можно вторым `Esc`.
  Future<void> submit() async {
    if (_running) {
      return;
    }
    error = null;

    final target = path.trim();
    if (target.isEmpty) {
      return;
    }

    _canceled = false;
    _running = true;
    // Подписка ставится до вызова: первую веху панель выставляет синхронно,
    // ещё внутри `openPath`, и подписавшийся после неё бы её не услышал.
    panel.addListener(_onPanelChanged);
    notifyListeners();

    try {
      final opened = await panel.openPath(target);

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
        error = (panel.error ?? FsError(target, FsErrorKind.notFound)).message;
        return;
      }
      remember(addressWithoutPassword(target));
      activate();
      close?.call();
    } on FsError catch (failure) {
      error = failure.message;
    } finally {
      panel.removeListener(_onPanelChanged);
      _running = false;
      _statusMessage = null;
      notifyListeners();
    }
  }

  /// `Esc` и «Cancel»: во время работы — прервать, в остальное время — закрыть.
  ///
  /// Отмена жёсткая, без вопроса «точно прервать?»: спрашивать стоит там, где
  /// сделанное необратимо (копирование посреди дерева), а подключение и чтение
  /// бросают, ничего не испортив.
  void dismiss() {
    if (_running) {
      _canceled = true;
      panel.cancel();
      return;
    }
    close?.call();
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
}

/// Поле пути, история под ним, строка о ходе работы и две кнопки.
class _OpenPathForm extends StatefulWidget {
  const _OpenPathForm({required this.state, required this.history});

  final OpenPathDialogState state;

  /// Куда уже ходили, свежие впереди. Пустая — окно выглядит как прежде.
  final List<String> history;

  @override
  State<_OpenPathForm> createState() => _OpenPathFormState();
}

class _OpenPathFormState extends State<_OpenPathForm> {
  late final TextEditingController _path = TextEditingController(text: widget.state.path)
    // Текущий путь выделен целиком: чаще его заменяют, чем правят, а если
    // правят — достаточно нажать стрелку.
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.state.path.length);

  /// Клавиши списка разбираются на самом поле — как в палитре.
  ///
  /// Стрелки иначе достались бы полю: оно двигает ими курсор внутри строки.
  late final FocusNode _field = FocusNode(debugLabel: 'open-path', onKeyEvent: _onKey);

  /// Набранное руками — то, чем отбирается список.
  ///
  /// Отбирает **оно**, а не содержимое поля: выбранное стрелкой попадает в
  /// поле целиком, и отбор по нему схлопнул бы список до одной строки — той
  /// самой, на которой стоишь.
  ///
  /// Пустая в начале, хотя в поле уже стоит путь панели: история показывается
  /// вся. Отбирать её текущим каталогом незачем — его как раз и заменяют.
  String _typed = '';

  /// Строка истории, на которой стоим; -1 — ни на какой, в поле набранное.
  int _selected = -1;

  /// Размер страницы для `PgUp`/`PgDn`: список меряет обзор и кладёт его сюда.
  final FcPickPage _page = FcPickPage();

  @override
  void dispose() {
    _path.dispose();
    _field.dispose();
    super.dispose();
  }

  List<FcPickRow> get _found =>
      FcPickList.filter([for (final path in widget.history) FcPickRow(id: path, title: path)], _typed);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final found = _found;
    // Без истории клавиши списка ничего не значат: пусть достаются полю.
    final moved = FcPickList.moveSelection(event, selected: _selected, count: found.length, wrap: false, page: _page);
    if (moved == null) {
      return KeyEventResult.ignored;
    }

    setState(() {
      _selected = moved;
      // Уход вверх с первой строки возвращает набранное: заглянуть в историю
      // не значит потерять то, что печатал.
      _write(moved < 0 ? _typed : found[moved].id);
    });
    return KeyEventResult.handled;
  }

  /// Вписать строку в поле — вместе с курсором в её конце.
  void _write(String value) {
    _path.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    widget.state.path = value;
  }

  /// Набор руками — это и новый отбор, и выход из списка.
  void _onChanged(String value) {
    widget.state.path = value;
    setState(() {
      _typed = value;
      _selected = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = FcTheme.of(context);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        // Подписи меряются здесь же, а не только внутри формы: список под полем
        // должен встать текстом ровно под ним, а поле стоит в столбце значений
        // — за подписью. Меряется тот же набор строк, что форма и покажет,
        // поэтому список и поле съезжают вместе или не съезжают вовсе.
        final labels = ['Path', if (state.statusMessage != null) 'Status'];
        final inset = dialogInputTextInset(context, labelWidth: widestLabel(context, labels));

        return CommandDialogForm(
          // Неудача не закрывает окно: путь правится тут же и пробуется снова.
          error: state.error,
          // Работа уже идёт — подтверждать нечего.
          busy: state.running,
          onCancel: state.dismiss,
          onSubmit: state.submit,
          submitLabel: 'Open',
          children: [
            CommandDialogField(
              label: 'Path',
              child: FcTextField(
                controller: _path,
                focusNode: _field,
                autofocus: true,
                // Поле остаётся живым и во время работы: выключенное отдало бы
                // фокус, а вернуть его после отмены было бы нечем — `autofocus`
                // срабатывает один раз.
                hintText: '/etc or ssh://user@host/srv',
                onChanged: _onChanged,
                onSubmitted: (_) => state.submit(),
              ),
            ),
            // История — под полем, как список в палитре. Нажатие мышью и
            // стрелка делают одно и то же: вписывают адрес в поле. Открывает
            // всегда `Enter`, и открывает он то, что в поле, — одно правило
            // вместо двух.
            if (widget.history.isNotEmpty)
              // Строка выбора идёт до самых краёв окна, мимо его полей: она
              // читается как «эта строка», а не «эта плитка». Отбит только
              // текст — и ровно под набранным в поле.
              CommandDialogField.bleed(
                child: ConstrainedBox(
                  // Окно не должно расти на всю историю: дальше список
                  // прокручивается.
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * theme.metrics.dialogWidthFactor,
                    maxHeight: (theme.metrics.rowHeight + theme.metrics.rowGap) * _visibleRows,
                  ),
                  child: FcPickList(
                    rows: _found,
                    query: _typed,
                    selected: _selected,
                    page: _page,
                    textInset: inset,
                    onTap: (address) {
                      _field.requestFocus();
                      setState(() {
                        _selected = _found.indexWhere((row) => row.id == address);
                        _write(address);
                      });
                    },
                    emptyMessage: 'No matching address in history',
                  ),
                ),
              ),
            // Чем занята панель прямо сейчас. Без этой строки открытие адреса
            // через сервер и два архива выглядит зависшим приложением: сказать о
            // ходе работы есть что, но говорится это в строке состояния панели —
            // под затенением этого самого окна.
            if (state.statusMessage case final message?)
              CommandDialogField(
                label: 'Status',
                // Одной строкой: адреса длинные, а окно не должно расти вниз на
                // каждой вехе.
                child: Text(message, style: theme.dialogTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        );
      },
    );
  }

  /// Сколько строк истории видно сразу.
  ///
  /// Десять — столько, чтобы список читался с одного взгляда и окно не
  /// вытеснило собой панель под ним.
  static const int _visibleRows = 10;
}
