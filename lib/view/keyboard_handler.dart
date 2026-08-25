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

  @override
  State<KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<KeyboardHandler> {
  /// Зажатые модификаторы: их показывает нижний ряд кнопок.
  ///
  /// Держатся здесь, потому что здесь и так проходят все события клавиатуры —
  /// включая одиночные нажатия модификаторов, у которых нет комбинации.
  final ValueNotifier<KeyModifiers> _modifiers = ValueNotifier(KeyModifiers.none);

  /// Узел, которому фокус достаётся, пока его никто не просил.
  ///
  /// На разбор клавиш он больше не влияет — только на то, чтобы фокус был хоть
  /// где-то и `Tab` не уводил его в неожиданное место.
  final FocusNode _node = FocusNode(debugLabel: 'KeyboardHandler');

  Application get app => widget.app;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    FocusManager.instance.addLateKeyEventHandler(_swallowEscape);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    FocusManager.instance.removeLateKeyEventHandler(_swallowEscape);
    _node.dispose();
    _modifiers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      // Фокус внутрь пускается всегда: раньше его приходилось запирать, чтобы
      // нажатия доставались обработчику, а тот теперь получает их первым в
      // любом случае. Вместе с запором ушла и вся возня с возвратом фокуса
      // после закрытия экрана, который его забирал.
      onFocusChange: (hasFocus) => _modifiers.value = hasFocus ? KeyModifiers.pressed() : KeyModifiers.none,
      child: ModifiersScope(modifiers: _modifiers, child: widget.child),
    );
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

    if (app.commands.openDialogs.isNotEmpty) {
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
