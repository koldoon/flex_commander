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

  /// В заголовке места больше, чем на кнопке в ряду.
  String get dialogTitle => 'Find text';

  @override
  bool isExecutable(CommandContext context) => finderOf(context.app) != null;

  /// Искать — или сперва спросить, что искать.
  ///
  /// Строку задают либо привязкой и сценарием, либо человеком в окне. Первый
  /// случай идёт мимо окна вовсе; во втором команда показывает окно и уходит,
  /// а состояние ввода живёт в самом окне.
  @override
  Future<void> execute(CommandContext context) async {
    final FcTextFinder? finder = finderOf(context.app);
    if (finder == null) {
      return;
    }

    final String? given = context.invocation.param<String>(patternParam);
    if (given != null) {
      final int count = await _run(context, finder, given);
      if (count == 0) {
        context.app.toasts.show('Not found: $given');
        return;
      }
      reportMatch(context.app, finder);
      return;
    }

    final view = context.app.view;
    final state = FcFindDialogState(
      finder: finder,
      pattern: finder.pattern,
      caseSensitive: finder.caseSensitive,
      regex: finder.regex,
      onFound: () => reportMatch(context.app, finder),
    );

    late final String dialogId;
    state.close = () => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: dialogTitle,
        takesFocus: true,
        content: _FindForm(state: state),
        onSubmit: state.submit,
        onDismiss: state.close,
      ),
    );
  }

  /// Условия поиска приходят тем же вызовом, что и строка: у команды-прототипа
  /// своего «как искать» нет.
  Future<int> _run(CommandContext context, FcTextFinder finder, String pattern) => finder.search(
    pattern,
    caseSensitive: context.invocation.param<bool>(caseSensitiveParam) ?? false,
    regex: context.invocation.param<bool>(regexParam) ?? false,
  );
}

/// Что набрано в окне поиска и что из этого вышло.
///
/// Живёт, пока открыто окно: команда, показав его, уходит. Ошибка остаётся
/// здесь же — не нашлось значит «поправь строку», а не «начинай заново».
///
/// Открыто наружу ради тестов: вся логика поиска теперь здесь, а проверить её
/// виджетным тестом нельзя — поиск считается в изоляте, а `flutter_test` живёт
/// на поддельном времени.
class FcFindDialogState extends ChangeNotifier {
  FcFindDialogState({
    required this.finder,
    required this.pattern,
    required this.caseSensitive,
    required this.regex,
    required this.onFound,
  });

  final FcTextFinder finder;
  final VoidCallback onFound;

  String pattern;
  bool caseSensitive;
  bool regex;
  String? error;

  /// Чем закрыть себя; ставится сразу после показа.
  /// null — окно ещё не показано (так бывает в тесте).
  VoidCallback? close;

  void update({String? pattern, bool? caseSensitive, bool? regex}) {
    this.pattern = pattern ?? this.pattern;
    this.caseSensitive = caseSensitive ?? this.caseSensitive;
    this.regex = regex ?? this.regex;
    notifyListeners();
  }

  /// Не нашлось — окно остаётся открытым.
  ///
  /// Иначе строку пришлось бы набирать заново из-за одной опечатки. Так же
  /// устроено открытие адреса: неудача остаётся в окне, а не закрывает его.
  Future<void> submit({bool backwards = false}) async {
    error = null;

    if (pattern.isEmpty) {
      error = 'Nothing to find';
      notifyListeners();
      return;
    }
    if (regex && !_isValidRegex(pattern)) {
      error = 'Not a valid expression';
      notifyListeners();
      return;
    }

    final int count = await finder.search(pattern, caseSensitive: caseSensitive, regex: regex);
    if (count == 0) {
      error = 'Not found: $pattern';
      notifyListeners();
      return;
    }

    if (backwards) {
      finder.previous();
    }
    onFound();
    close?.call();
  }

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
  Future<void> execute(CommandContext context) async {
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
  Future<void> execute(CommandContext context) async {
    final FcTextFinder? finder = finderOf(context.app);
    if (finder == null || !finder.previous()) {
      return;
    }
    reportMatch(context.app, finder);
  }
}

/// Одно поле, два флажка и две кнопки.
class _FindForm extends StatefulWidget {
  const _FindForm({required this.state});

  final FcFindDialogState state;

  @override
  State<_FindForm> createState() => _FindFormState();
}

class _FindFormState extends State<_FindForm> {
  late final TextEditingController _pattern = TextEditingController(text: widget.state.pattern)
    // Прошлая строка выделена целиком: повторить поиск — нажатие, а набрать
    // новую можно поверх.
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.state.pattern.length);

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return ListenableBuilder(
      listenable: state,
      builder:
          (context, _) => CommandDialogForm(
            error: state.error,
            onCancel: state.close ?? () {},
            onSubmit: state.submit,
            submitLabel: 'Find',
            children: [
              CommandDialogField(
                label: 'Text',
                // `Shift-Enter` ищет назад. Рама окна пропускает его мимо себя —
                // она знает только про чистый `Enter`, — и он достаётся полю.
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => state.submit(backwards: true),
                  },
                  child: FcTextField(
                    controller: _pattern,
                    autofocus: true,
                    hintText: 'text to find',
                    onChanged: (value) => state.pattern = value,
                    onSubmitted: (_) => state.submit(),
                  ),
                ),
              ),
              CommandDialogField.wide(
                child: FcCheckbox(
                  label: 'Case sensitive',
                  value: state.caseSensitive,
                  onChanged: (value) => state.update(caseSensitive: value),
                ),
              ),
              CommandDialogField.wide(
                child: FcCheckbox(
                  label: 'Regular expression',
                  value: state.regex,
                  onChanged: (value) => state.update(regex: value),
                ),
              ),
            ],
          ),
    );
  }
}
