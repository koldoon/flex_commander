import 'package:xterm/xterm.dart';

/// Курсорные клавиши в прикладном режиме.
///
/// Программы полного экрана — `mc`, `vim`, `less` — просят терминал переключить
/// стрелки в прикладной режим (`DECCKM`, `ESC [ ? 1 h`) и ждут `ESC O A` вместо
/// обычного `ESC [ A`. Именно эти последовательности стоят в их описании
/// терминала (`terminfo`, `kcuu1`), и по обычным они стрелку не узнают: в `mc`
/// курсор просто не двигается.
///
/// `xterm` этот режим **запоминает** ([Terminal.cursorKeysMode]), но при
/// кодировании нажатий не смотрит: его обработчик спрашивает совсем другой
/// режим — прикладную цифровую клавиатуру. Правка в чужом пакете, поэтому
/// поправлено здесь, своим обработчиком поверх стандартного.
class AppCursorKeys implements TerminalInputHandler {
  const AppCursorKeys(this._terminal);

  final Terminal _terminal;

  /// Что уходит программе, когда режим включён.
  static const Map<TerminalKey, String> _codes = {
    TerminalKey.arrowUp: '\x1bOA',
    TerminalKey.arrowDown: '\x1bOB',
    TerminalKey.arrowRight: '\x1bOC',
    TerminalKey.arrowLeft: '\x1bOD',
    // `Home` и `End` тем же режимом и переключаются: `mc` берёт их оттуда же.
    TerminalKey.home: '\x1bOH',
    TerminalKey.end: '\x1bOF',
  };

  @override
  String? call(TerminalKeyboardEvent event) {
    // С модификаторами последовательность другая (`ESC [ 1 ; 5 A` и подобные),
    // и собирает её стандартный обработчик — ему и отдаём.
    if (!_terminal.cursorKeysMode || event.ctrl || event.alt || event.shift) {
      return null;
    }
    return _codes[event.key];
  }
}
