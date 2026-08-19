import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:fc_api/fc_api.dart';

/// Приём клавиатуры для всего окна.
///
/// Обработчик один: активная панель определяется [AppController], а не
/// системным фокусом, поэтому панели своих обработчиков не имеют и бороться
/// с `FocusManager` не приходится (в референсе с этим боролись вручную).
class KeyboardHandler extends StatelessWidget {
  const KeyboardHandler({super.key, required this.app, required this.child});

  final Application app;
  final Widget child;

  /// Пока панель занята длительной операцией, работает только отмена.
  static const String cancelKey = 'Esc';

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      // Обычная навигация по фокусу приложению не нужна: Tab переключает
      // панели, а не перескакивает на кнопки внизу окна.
      canRequestFocus: true,
      descendantsAreFocusable: false,
      onKeyEvent: _handleKey,
      child: child,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
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

    if (app.activePanel.busy && combination.key != cancelKey) {
      // Событие считается обработанным: пока идёт чтение, клавиши не должны
      // проваливаться дальше и, например, уводить фокус по Tab.
      return KeyEventResult.handled;
    }

    app.commands.dispatch(combination);

    // Событие считается обработанным, даже когда команды под него нет.
    //
    // Иначе оно уходит дальше — в AppKit, — а тот на `Cmd+.` отвечает
    // «отменить операцию» и присылает приложению Escape. Наш обработчик Escape
    // тоже не тратит (пока панель свободна, отменять нечего), событие снова
    // уходит в AppKit — и так по кругу: одно нажатие давало **больше тридцати
    // тысяч** событий Escape подряд.
    //
    // Пока шёл этот поток, любое чтение каталога успевало отмениться первым же
    // Escape — вход в каталог по Enter выглядел как «ничего не произошло».
    //
    // Терять на этом нечего: клавиши окна принадлежат приложению целиком.
    // Сочетания меню (`Cmd+Q`, `Cmd+W`, `Cmd+M`) сюда и не попадают — их
    // разбирает строка меню до того, как событие дойдёт до Flutter.
    return KeyEventResult.handled;
  }
}
