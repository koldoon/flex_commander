import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

/// Модификаторы, зажатые прямо сейчас.
///
/// Нужны нижнему ряду кнопок: пока держат Shift, ряд показывает не «чистые»
/// `F1`…`F10`, а их слой — `Shift-F5`, `Shift-F7` и так далее.
@immutable
class KeyModifiers {
  const KeyModifiers({this.ctrl = false, this.alt = false, this.shift = false, this.cmd = false});

  /// Что зажато сейчас — по состоянию самой клавиатуры.
  ///
  /// Именно спрашивается, а не накапливается по событиям: свой счёт разойдётся
  /// с настоящим, стоит пропасть одному событию, — а они пропадают. На macOS,
  /// пока удерживается Cmd, отпускание других клавиш не приходит вовсе.
  factory KeyModifiers.pressed() {
    final keyboard = HardwareKeyboard.instance;
    return KeyModifiers(
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      cmd: keyboard.isMetaPressed,
    );
  }

  static const KeyModifiers none = KeyModifiers();

  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool cmd;

  /// Ничего не зажато — базовый слой.
  bool get isEmpty => !ctrl && !alt && !shift && !cmd;

  /// Комбинация этой клавиши в текущем слое.
  KeyCombination on(String key) => KeyCombination(key, ctrl: ctrl, alt: alt, shift: shift, cmd: cmd);

  @override
  bool operator ==(Object other) =>
      other is KeyModifiers && other.ctrl == ctrl && other.alt == alt && other.shift == shift && other.cmd == cmd;

  @override
  int get hashCode => Object.hash(ctrl, alt, shift, cmd);

  @override
  String toString() =>
      isEmpty ? 'нет' : [if (ctrl) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', if (cmd) 'Cmd'].join('-');
}

/// Зажатые модификаторы — для тех, кто ниже по дереву.
///
/// Обычный [InheritedNotifier], как [AppScope]: следит за состоянием клавиатуры
/// один обработчик, а пользуется им нижний ряд кнопок.
class ModifiersScope extends InheritedNotifier<ValueNotifier<KeyModifiers>> {
  const ModifiersScope({super.key, required ValueNotifier<KeyModifiers> modifiers, required super.child})
    : super(notifier: modifiers);

  /// Зажатое сейчас; пусто, если следить некому — так виджет остаётся
  /// пригодным и вне окна приложения (в тестах, в отдельном снимке).
  static KeyModifiers of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ModifiersScope>();
    return scope?.notifier?.value ?? KeyModifiers.none;
  }
}
