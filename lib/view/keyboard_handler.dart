import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';

import 'modifiers_scope.dart';

/// Приём клавиатуры для всего окна.
///
/// Нажатие разбирается **раньше дерева фокуса**
/// ([FocusManager.addEarlyKeyEventHandler]), а не после него. Разница
/// принципиальная: обработчик больше не обязан быть тем, у кого фокус, и не
/// обязан отбирать его обратно. Кто владеет фокусом — редактор, поле ввода в
/// окне, прокрутка просмотрщика, — на разбор привязок не влияет вовсе.
///
/// Уровня три, и порядок между ними существенен:
///
/// 1. **Рано** — привязки приложения. Пока открыто окно команды, этот уровень
///    молчит: клавиши принадлежат окну. Пока панель занята — пропускает только
///    отмену.
/// 2. **Дерево фокуса** — всё, для чего привязки нет: печать в редакторе,
///    прокрутка стрелками в просмотрщике, `Esc` в открытом окне и в вопросе по
///    ходу работы.
/// 3. **Поздно** — `Esc`, который никто не взял, гасится здесь и наружу не
///    уходит.
///
/// Гасить `Esc` рано нельзя: тогда он не дошёл бы ни до окна, ни до вопроса.
class KeyboardHandler extends StatefulWidget {
  const KeyboardHandler({super.key, required this.app, required this.child});

  final Application app;
  final Widget child;

  /// Пока панель занята длительной операцией, работает только отмена.
  static const String cancelKey = 'Esc';

  /// Уйти с занятой панели можно всегда.
  ///
  /// Занятость — свойство **панели**, а не приложения: соседняя живёт своей
  /// жизнью, и запирать человека в читающей панели незачем. Ушли — активной
  /// стала свободная, и там снова работает всё.
  static const String leaveKey = 'Tab';

  /// Что проходит сквозь занятость: прервать работу и уйти от неё.
  static const Set<String> keysWhileBusy = {cancelKey, leaveKey};

  @override
  State<KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<KeyboardHandler> {
  /// Зажатые модификаторы: их показывает нижний ряд кнопок.
  ///
  /// Держатся здесь, потому что здесь и так проходят все события клавиатуры —
  /// включая одиночные нажатия модификаторов, у которых нет комбинации.
  final ValueNotifier<KeyModifiers> _modifiers = ValueNotifier(KeyModifiers.none);

  Application get app => widget.app;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    FocusManager.instance.addLateKeyEventHandler(_swallowEscape);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    FocusManager.instance.removeLateKeyEventHandler(_swallowEscape);
    FocusManager.instance.removeListener(_onFocusChanged);
    _modifiers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Фокуса себе не просит вовсе: нажатия он получает раньше дерева фокуса,
      // и владелец фокуса на разбор не влияет. Раньше приходилось и держать
      // фокус, и запирать его внутри, и отбирать обратно после закрытия
      // экрана, который его забирал, — всё это ушло.
      canRequestFocus: false,
      skipTraversal: true,
      child: ModifiersScope(modifiers: _modifiers, child: widget.child),
    );
  }

  /// Фокус остался ничьим — окно ушло к соседнему приложению.
  ///
  /// Слой модификаторов сбрасывается: отпускание случится уже там и до нас не
  /// дойдёт, а ряд кнопок иначе остался бы в чужом слое навсегда.
  ///
  /// «Ничей» — это область, а не обычный узел: у настоящего хозяина узел
  /// обычный. Зажатый модификатор от этого не теряется — его снимает каждое
  /// нажатие, а смена фокуса при удержании не происходит.
  void _onFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus is FocusScopeNode) {
      _modifiers.value = KeyModifiers.none;
    }
  }

  KeyEventResult _handleKey(KeyEvent event) {
    // Снимается до всех проверок и ранних выходов: модификатор отпускают и
    // тогда, когда открыто окно команды, — а ряд кнопок не должен остаться в
    // чужом слое. Состояние читается у `HardwareKeyboard`, а не копится из
    // событий: на macOS отпускание не приходит, пока держат Cmd.
    _modifiers.value = KeyModifiers.pressed();

    // Автоповтор обрабатывается наравне с нажатием: иначе удержание стрелки
    // не двигает курсор.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (app.view.dialogs.isNotEmpty) {
      // Пока открыто окно команды, клавиши принадлежат ему целиком, и
      // обработчик отходит в сторону — включая `Esc`. Иначе `Esc` не дошёл бы
      // ни до окна, ни до вопроса по ходу работы: обработчик забрал бы его
      // раньше, чем дерево фокуса.
      return KeyEventResult.ignored;
    }

    final combination = KeyCombination.fromEvent(event);
    if (combination == null) {
      return KeyEventResult.ignored;
    }

    // Занятость глушит клавиши только там, где стоит занятая панель: чужое
    // содержимое читает свой файл и о чтении каталога ничего не знает.
    final panel = app.view.panelAt(app.view.activeArea);
    if (panel != null && panel.busy && !KeyboardHandler.keysWhileBusy.contains(combination.key)) {
      // Событие считается обработанным: пока идёт чтение, клавиши не должны
      // проваливаться дальше — ни в поле ввода, ни в обход фокуса. Уводит
      // отсюда только `Tab`, и уводит он не фокусом, а сменой активной панели:
      // команда за ним стоит и занятости не спрашивает.
      return KeyEventResult.handled;
    }

    if (app.commands.dispatch(combination)) {
      return KeyEventResult.handled;
    }

    // Команды под клавишу не нашлось — пропускаем дальше: в поле ввода, в
    // прокрутку, а оттуда в систему. `Cmd+Q`, `Cmd+W` и прочие меню Flutter
    // спрашивает у приложения раньше, чем строку меню, и «обработано» их
    // отменяет. `Esc` в том числе: он ещё нужен окну и вопросу.
    return KeyEventResult.ignored;
  }

  /// Третий уровень: `Esc`, который не взял никто.
  ///
  /// Наружу его пускать нельзя. AppKit понимает `Cmd+.` как «отменить
  /// операцию» и присылает в ответ Escape; если и его вернуть неразобранным,
  /// он уйдёт обратно в AppKit, тот снова ответит Escape — и так по кругу.
  /// Одно нажатие `Cmd+.` давало больше тридцати тысяч событий подряд, а
  /// каждое из них отменяло начатое чтение каталога: вход по Enter выглядел
  /// как «ничего не произошло».
  ///
  /// Здесь, а не на первом уровне: `Esc` — клавиша приложения, но сначала он
  /// принадлежит тому, кто на экране. Гасить его рано значило бы никогда не
  /// донести до окна и до вопроса по ходу работы.
  KeyEventResult _swallowEscape(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final combination = KeyCombination.fromEvent(event);
    return combination?.key == KeyboardHandler.cancelKey ? KeyEventResult.handled : KeyEventResult.ignored;
  }
}
