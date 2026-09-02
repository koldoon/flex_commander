import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Комбинация клавиш в нормализованном виде.
///
/// Строковая форма — не украшательство: в ней хранятся привязки в настройках,
/// и в ней же пользователь будет их переопределять. Порядок модификаторов
/// фиксирован: `Ctrl-Alt-Shift-Cmd-Клавиша`.
@immutable
class KeyCombination {
  const KeyCombination(
    this.key, {
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.cmd = false,
    this.character,
  });

  /// Нормализованное имя клавиши: `Enter`, `F5`, `Bsp`, `A`, `/`.
  final String key;

  final bool ctrl;
  final bool alt;
  final bool shift;

  /// Символ, который дала раскладка: `l`, `L`, `!`, `ф`.
  ///
  /// Отдельно от [key] и **не участвует в сравнении**: клавиша — это то, за чем
  /// закреплена команда, а символ — то, что человек напечатал. Имя клавиши
  /// приведено к верхнему регистру и от раскладки не зависит, поэтому взять
  /// печатное из него нельзя: `ls` превратилось бы в `LS`, а `!` — в `1`.
  ///
  /// null — нажатие символа не дало (стрелка, `F5`) или комбинацию собрали
  /// вручную: в тесте, в настройках, в сценарии.
  final String? character;

  /// Command на macOS. На остальных платформах роль этой клавиши играет Ctrl,
  /// поэтому при разборе строки `Cmd-O` там получается `Ctrl-O`.
  final bool cmd;

  /// Особая комбинация «любой печатный символ» — для привязок вроде перехода
  /// к имени по набранной букве. Настоящей клавиши с таким названием нет:
  /// [_nameOf] возвращает либо одиночный символ, либо имя из [_specialKeys].
  static const KeyCombination anyCharacter = KeyCombination('AnyChar');

  /// Печатный символ: буква, цифра, знак. Shift допускается — это тот же
  /// символ, только заглавный; остальные модификаторы делают из нажатия
  /// сочетание, а не ввод символа.
  bool get isCharacter => key.length == 1 && !ctrl && !alt && !cmd;

  /// Функциональная клавиша: `F1`…`F12`.
  ///
  /// Нужно тем, кто решает, кому клавиша принадлежит: ряд кнопок обещает
  /// именно их, и текстовый ввод не использует ни одной.
  bool get isFunctionKey => _functionKeyRe.hasMatch(key);

  static final RegExp _functionKeyRe = RegExp(r'^F\d+$');

  static bool get _isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  /// Комбинация из события клавиатуры; null, если нажат только модификатор.
  static KeyCombination? fromEvent(KeyEvent event) {
    final name = _nameOf(event.logicalKey);
    if (name == null) {
      return null;
    }
    final keyboard = HardwareKeyboard.instance;
    return KeyCombination(
      name,
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      cmd: keyboard.isMetaPressed,
      character: event.character,
    );
  }

  factory KeyCombination.parse(String value) {
    // Разделитель и сама клавиша совпадают: `-` — это минус, а `Cmd--` — минус
    // с модификатором. Обычным разбором такое не выразить, поэтому этот случай
    // разбирается первым: строка кончается разделителем, значит клавиша и есть
    // разделитель.
    final minus = value.endsWith('-');
    final parts = (minus ? value.substring(0, value.length - 1) : value).split('-')
      ..removeWhere((part) => minus && part.isEmpty);
    final key = minus ? '-' : parts.removeLast();
    var ctrl = false;
    var alt = false;
    var shift = false;
    var cmd = false;

    for (final part in parts) {
      switch (part.toLowerCase()) {
        case 'ctrl':
          ctrl = true;
        case 'alt':
          alt = true;
        case 'shift':
          shift = true;
        case 'cmd':
          // На Windows и Linux привычная «командная» клавиша — Ctrl.
          if (_isMacOS) {
            cmd = true;
          } else {
            ctrl = true;
          }
        default:
          throw FormatException('Неизвестный модификатор «$part» в «$value»');
      }
    }

    return KeyCombination(key, ctrl: ctrl, alt: alt, shift: shift, cmd: cmd);
  }

  @override
  String toString() => [if (ctrl) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', if (cmd) 'Cmd', key].join('-');

  @override
  bool operator ==(Object other) =>
      other is KeyCombination &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift &&
      other.cmd == cmd;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift, cmd);

  static String? _nameOf(LogicalKeyboardKey logicalKey) {
    final special = _specialKeys[logicalKey];
    if (special != null) {
      return special;
    }
    if (_modifiers.contains(logicalKey)) {
      return null;
    }

    final label = logicalKey.keyLabel;
    // Клавиши без печатного обозначения (Fn, CapsLock и прочие) пропускаем:
    // привязок к ним нет, а в комбинацию они попадать не должны.
    return label.length == 1 ? label.toUpperCase() : null;
  }

  static final Map<LogicalKeyboardKey, String> _specialKeys = {
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.backspace: 'Bsp',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.arrowUp: 'Up',
    LogicalKeyboardKey.arrowDown: 'Down',
    LogicalKeyboardKey.arrowLeft: 'Left',
    LogicalKeyboardKey.arrowRight: 'Right',
    LogicalKeyboardKey.pageUp: 'PgUp',
    LogicalKeyboardKey.pageDown: 'PgDn',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.insert: 'Ins',
    LogicalKeyboardKey.delete: 'Del',
    LogicalKeyboardKey.f1: 'F1',
    LogicalKeyboardKey.f2: 'F2',
    LogicalKeyboardKey.f3: 'F3',
    LogicalKeyboardKey.f4: 'F4',
    LogicalKeyboardKey.f5: 'F5',
    LogicalKeyboardKey.f6: 'F6',
    LogicalKeyboardKey.f7: 'F7',
    LogicalKeyboardKey.f8: 'F8',
    LogicalKeyboardKey.f9: 'F9',
    LogicalKeyboardKey.f10: 'F10',
    LogicalKeyboardKey.f11: 'F11',
    LogicalKeyboardKey.f12: 'F12',
  };

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };
}
