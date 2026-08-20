import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';

import 'modifiers_scope.dart';

/// Приём клавиатуры для всего окна.
///
/// Обработчик один: активная панель определяется [AppController], а не
/// системным фокусом, поэтому панели своих обработчиков не имеют и бороться
/// с `FocusManager` не приходится (в референсе с этим боролись вручную).
class KeyboardHandler extends StatefulWidget {
  const KeyboardHandler({super.key, required this.app, required this.child});

  final Application app;
  final Widget child;

  /// Пока панель занята длительной операцией, работает только отмена.
  static const String cancelKey = 'Esc';

  @override
  State<KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<KeyboardHandler> {
  /// Зажатые модификаторы: их показывает нижний ряд кнопок.
  ///
  /// Держатся здесь, потому что здесь и так проходят все события клавиатуры —
  /// включая одиночные нажатия модификаторов, у которых нет комбинации.
  final ValueNotifier<KeyModifiers> _modifiers = ValueNotifier(KeyModifiers.none);

  /// Свой узел фокуса: его приходится забирать обратно — см. [_reclaimFocus].
  final FocusNode _node = FocusNode(debugLabel: 'KeyboardHandler');

  Application get app => widget.app;

  /// Экран, который был виден в прошлый раз, — чтобы заметить уход того,
  /// кто забирал фокус.
  Screen? _lastScreen;

  /// Ждём, что осиротевший фокус достанется нам.
  bool _awaitingFocus = false;

  @override
  void initState() {
    super.initState();
    _lastScreen = app.screens.active;
    app.screens.addListener(_onScreenChanged);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    app.screens.removeListener(_onScreenChanged);
    _node.dispose();
    _modifiers.dispose();
    super.dispose();
  }

  /// Экран, забиравший фокус, ушёл — ждём фокус обратно.
  ///
  /// Такой экран (редактор) уносит с собой узел, у которого фокус был, а
  /// объемлющая область истории не помнит: фокус достаётся ей самой, то есть
  /// никому, и приложение перестаёт слышать клавиатуру целиком. Снаружи это
  /// выглядит как зависшее окно.
  void _onScreenChanged() {
    final was = _lastScreen;
    _lastScreen = app.screens.active;
    if (was != null && was.takesFocus && !identical(was, _lastScreen)) {
      _awaitingFocus = true;
    }
  }

  /// Забирает осиротевший фокус — но только после ухода такого экрана.
  ///
  /// Ждать в общем случае нельзя: фокус уходит и по делу — в окно команды, в
  /// вопрос о пароле, в соседнее приложение по `Cmd-Tab`. Отбирать его там
  /// значило бы не давать печатать и оставлять ряд кнопок в чужом слое.
  void _onFocusChanged() {
    if (!_awaitingFocus) {
      return;
    }
    _awaitingFocus = false;

    // Фокус у области, а не у обычного узла, — значит им никто не владеет:
    // у настоящего хозяина узел обычный.
    if (FocusManager.instance.primaryFocus is FocusScopeNode && mounted && _wantsFocus) {
      _node.requestFocus();
    }
  }

  /// Должен ли фокус быть у обработчика прямо сейчас.
  ///
  /// Не должен, пока открыто окно команды или вопрос о пароле (в их полях
  /// нужно печатать) и пока открыт экран, которому фокус нужен самому.
  bool get _wantsFocus =>
      app.commands.openDialogs.isEmpty && app.credentials.pending == null && !(app.screens.active?.takesFocus ?? false);

  @override
  Widget build(BuildContext context) {
    // Подписка на экраны: от того, какой из них сверху, зависит, пускать ли
    // фокус внутрь, — а смена экрана обработчик иначе не заметит.
    return ListenableBuilder(
      listenable: app.screens,
      builder: (context, child) {
        return Focus(
          focusNode: _node,
          autofocus: true,
          // Обычная навигация по фокусу приложению не нужна: Tab переключает
          // панели, а не перескакивает на кнопки внизу окна.
          canRequestFocus: true,
          // Кроме случая, когда фокус нужен самому экрану: просмотрщику его
          // прокрутка разбирает стрелки и PgUp/PgDn сама, и до неё события
          // должны доходить. Нажатия, которые она не взяла, всплывают сюда же.
          descendantsAreFocusable: app.screens.active?.takesFocus ?? false,
          onKeyEvent: _handleKey,
          // Уход фокуса сбрасывает слой: отпускание клавиши случится уже в
          // чужом окне и до нас не дойдёт, а ряд иначе остался бы в слое
          // навсегда.
          // Уход фокуса сбрасывает слой модификаторов; забирать фокус обратно
          // здесь нельзя — он уходит и по делу: в окно команды, в вопрос о
          // пароле, в соседнее приложение.
          onFocusChange: (hasFocus) => _modifiers.value = hasFocus ? KeyModifiers.pressed() : KeyModifiers.none,
          child: child!,
        );
      },
      child: ModifiersScope(modifiers: _modifiers, child: widget.child),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // Снимается до всех проверок и ранних выходов: модификатор отпускают и
    // тогда, когда открыто окно команды, — а ряд кнопок не должен остаться в
    // чужом слое.
    _modifiers.value = KeyModifiers.pressed();

    // Автоповтор обрабатывается наравне с нажатием: иначе удержание стрелки
    // не двигает курсор.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final combination = KeyCombination.fromEvent(event);
    if (combination == null) {
      return KeyEventResult.ignored;
    }

    if (app.commands.openDialogs.isNotEmpty) {
      // Пока открыто окно команды, клавиши принадлежат ему. Обычно фокус и так
      // у окна, но правило должно быть явным: панели не должны реагировать на
      // ввод из-под чужого окна.
      return KeyEventResult.ignored;
    }

    // Занятость панели глушит клавиши только на самой панели: чужой экран
    // читает свой файл и о чтении каталога ничего не знает.
    final onPanels = app.screens.active?.id == Screens.files;
    if (onPanels && app.activePanel.busy && combination.key != KeyboardHandler.cancelKey) {
      // Событие считается обработанным: пока идёт чтение, клавиши не должны
      // проваливаться дальше и, например, уводить фокус по Tab.
      return KeyEventResult.handled;
    }

    if (app.commands.dispatch(combination)) {
      return KeyEventResult.handled;
    }

    // Команды под клавишу не нашлось. Обычно такое событие надо пропустить
    // дальше — иначе система не получит своих сочетаний: `Cmd+Q`, `Cmd+W` и
    // прочие меню Flutter спрашивает у приложения раньше, чем строку меню, и
    // «обработано» их отменяет.
    //
    // Но Escape наружу пускать нельзя. AppKit понимает `Cmd+.` как «отменить
    // операцию» и присылает в ответ Escape; если и его вернуть неразобранным,
    // он уйдёт обратно в AppKit, тот снова ответит Escape — и так по кругу.
    // Одно нажатие `Cmd+.` давало больше тридцати тысяч событий подряд, а
    // каждое из них отменяло начатое чтение каталога: вход по Enter выглядел
    // как «ничего не произошло».
    //
    // Escape — клавиша приложения (отмена операции, снятие пометки), и то, что
    // сейчас ей нечего делать, ничего не меняет: наружу ей всё равно не надо.
    return combination.key == KeyboardHandler.cancelKey ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}
