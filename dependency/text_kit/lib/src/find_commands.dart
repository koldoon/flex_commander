import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'text_finder.dart';

/// Как команда находит поисковик своего экрана.
///
/// Экран спрашивается не по типу, а по [FcSearchable]: просмотрщик и редактор
/// показывают текст одинаково, значит и ищут одинаково.
mixin _ScreenFinder on AppCommand {
  /// Экран, которому команда принадлежит. Приходит из модуля: тот знает и своё
  /// имя экрана, и свои идентификаторы команд.
  String get screenId;

  FcTextFinder? finderOf(Application app) {
    final ViewportState? screen = app.view.contentAt(ViewportPosition.fullscreen);
    return screen is FcSearchable && screen.id == screenId ? screen.finder : null;
  }

  /// Сколько нашлось и которое показано — сообщением.
  ///
  /// Постоянной панели поиска у нас нет, и счёт сказать больше негде; а знать
  /// его нужно, иначе непонятно, ходишь ты по кругу или стоишь на месте.
  void reportMatch(Application app, FcTextFinder finder) =>
      app.toasts.show('Match ${finder.currentIndex} of ${finder.matchCount}');
}

/// Найти строку в показанном тексте.
///
/// Строку спрашивает окно — такое же, как у остальных команд приложения.
/// Постоянной панели поиска нет нарочно: она заслоняет текст, а всё, что ей
/// полагалось бы показывать, говорится иначе — найденное подсвечено, счёт
/// уходит сообщением, ход по совпадениям на клавишах.
class FcFindTextCommand extends AppCommand with _ScreenFinder {
  FcFindTextCommand({required String id, required this.screenId}) : _id = id;

  /// Что ищем — окно кладёт сюда по мере набора.
  static const String patternParam = 'pattern';
  static const String caseSensitiveParam = 'caseSensitive';
  static const String regexParam = 'regex';

  /// Искать назад: `Shift-Enter` в окне.
  static const String backwardsParam = 'backwards';

  final String _id;

  @override
  final String screenId;

  @override
  String get id => _id;

  @override
  String get label => 'Find';

  @override
  String get description => 'Find text in the document';

  /// Окно есть: строку спрашивают у человека.
  @override
  bool get hasDialog => true;

  /// В заголовке места больше, чем на кнопке в ряду.
  @override
  String get dialogTitle => 'Find text';

  @override
  bool isExecutable(CommandContext context) => finderOf(context.app) != null;

  @override
  Future<void> execute() async {
    final FcTextFinder? finder = finderOf(context.app);
    if (finder == null) {
      return;
    }

    final String pattern = param<String>(patternParam) ?? '';
    final int count = await _run(finder, pattern);
    if (count == 0) {
      context.app.toasts.show('Not found: $pattern');
      return;
    }
    reportMatch(context.app, finder);
  }

  /// Подтверждение окна: не нашлось — окно остаётся открытым.
  ///
  /// Иначе строку пришлось бы набирать заново из-за одной опечатки. Так же
  /// устроено открытие адреса: неудача остаётся в окне, а не закрывает его.
  @override
  Future<void> submit() async {
    error = null;

    final FcTextFinder? finder = finderOf(context.app);
    if (finder == null) {
      return;
    }

    final String pattern = param<String>(patternParam) ?? '';
    if (pattern.isEmpty) {
      error = 'Nothing to find';
      return;
    }
    if (param<bool>(regexParam) == true && !_isValidRegex(pattern)) {
      error = 'Not a valid expression';
      return;
    }

    if (await _run(finder, pattern) == 0) {
      error = 'Not found: $pattern';
      return;
    }

    if (param<bool>(backwardsParam) == true) {
      finder.previous();
    }
    reportMatch(context.app, finder);
    closeDialog();
  }

  @override
  Widget? getDialog(BuildContext context) =>
      ListenableBuilder(listenable: this, builder: (context, _) => _FindForm(command: this));

  Future<int> _run(FcTextFinder finder, String pattern) => finder.search(
    pattern,
    caseSensitive: param<bool>(caseSensitiveParam) ?? false,
    regex: param<bool>(regexParam) ?? false,
  );

  static bool _isValidRegex(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } on FormatException {
      return false;
    }
  }
}

/// Следующее совпадение — по кругу.
class FcFindNextCommand extends AppCommand with _ScreenFinder {
  FcFindNextCommand({required String id, required this.screenId}) : _id = id;

  final String _id;

  @override
  final String screenId;

  @override
  String get id => _id;

  @override
  String get label => 'Find Next';

  @override
  String get description => 'Go to the next match';

  /// Пока не искали, ходить не по чему — кнопка в ряду приглушена.
  @override
  bool isExecutable(CommandContext context) => (finderOf(context.app)?.matchCount ?? 0) > 0;

  @override
  Future<void> execute() async {
    final FcTextFinder? finder = finderOf(context.app);
    if (finder == null || !finder.next()) {
      return;
    }
    reportMatch(context.app, finder);
  }
}

/// Предыдущее совпадение — по кругу.
class FcFindPreviousCommand extends AppCommand with _ScreenFinder {
  FcFindPreviousCommand({required String id, required this.screenId}) : _id = id;

  final String _id;

  @override
  final String screenId;

  @override
  String get id => _id;

  @override
  String get label => 'Find Previous';

  @override
  String get description => 'Go to the previous match';

  @override
  bool isExecutable(CommandContext context) => (finderOf(context.app)?.matchCount ?? 0) > 0;

  @override
  Future<void> execute() async {
    final FcTextFinder? finder = finderOf(context.app);
    if (finder == null || !finder.previous()) {
      return;
    }
    reportMatch(context.app, finder);
  }
}

/// Одно поле, два флажка и две кнопки.
class _FindForm extends StatefulWidget {
  const _FindForm({required this.command});

  final FcFindTextCommand command;

  @override
  State<_FindForm> createState() => _FindFormState();
}

class _FindFormState extends State<_FindForm> {
  late final FcTextFinder? _finder = widget.command.finderOf(AppScope.read(context));

  late final TextEditingController _pattern = TextEditingController(text: _finder?.pattern ?? '')
    // Прошлая строка выделена целиком: повторить поиск — нажатие, а набрать
    // новую можно поверх.
    ..selection = TextSelection(baseOffset: 0, extentOffset: _finder?.pattern.length ?? 0);

  late bool _caseSensitive = _finder?.caseSensitive ?? false;
  late bool _regex = _finder?.regex ?? false;

  @override
  void initState() {
    super.initState();
    // Значения задаются сразу: Enter обрабатывает рама окна, и к моменту
    // подтверждения параметры уже должны быть на месте.
    _push();
  }

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  void _push() {
    widget.command
      ..setParam(FcFindTextCommand.patternParam, _pattern.text)
      ..setParam(FcFindTextCommand.caseSensitiveParam, _caseSensitive)
      ..setParam(FcFindTextCommand.regexParam, _regex);
  }

  void _submit({bool backwards = false}) {
    widget.command
      ..setParam(FcFindTextCommand.backwardsParam, backwards)
      ..submit();
  }

  @override
  Widget build(BuildContext context) {
    return CommandDialogForm(
      error: widget.command.error,
      onCancel: widget.command.dismiss,
      onSubmit: _submit,
      submitLabel: 'Find',
      children: [
        CommandDialogField(
          label: 'Text',
          // `Shift-Enter` ищет назад. Рама окна пропускает его мимо себя —
          // она знает только про чистый `Enter`, — и он достаётся полю.
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => _submit(backwards: true)},
            child: FcTextField(
              controller: _pattern,
              autofocus: true,
              hintText: 'text to find',
              onChanged: (value) {
                widget.command.setParam(FcFindTextCommand.patternParam, value);
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        FcCheckbox(
          label: 'Case sensitive',
          value: _caseSensitive,
          onChanged:
              (value) => setState(() {
                _caseSensitive = value;
                _push();
              }),
        ),
        FcCheckbox(
          label: 'Regular expression',
          value: _regex,
          onChanged:
              (value) => setState(() {
                _regex = value;
                _push();
              }),
        ),
      ],
    );
  }
}
