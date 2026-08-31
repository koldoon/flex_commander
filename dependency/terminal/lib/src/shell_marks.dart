import 'dart:math';

/// Что оболочка сообщила о законченной команде.
///
/// Приходит перед каждым приглашением, а не после каждой команды: приглашение —
/// единственное, что оболочка печатает предсказуемо.
class ShellMark {
  const ShellMark({required this.exitCode, required this.directory});

  /// Код возврата последней команды.
  final int exitCode;

  /// Где оболочка оказалась. Пусто — не сказала.
  final String directory;

  @override
  String toString() => 'ShellMark($exitCode, $directory)';
}

/// Уговор с оболочкой: отмечать каждое приглашение кодом возврата и каталогом.
///
/// **Зачем.** В постоянной сессии конец команды перестаёт быть событием:
/// процесс не завершается, оболочка просто печатает приглашение, а отличить
/// приглашение от вывода `grep` нечем. Без этого рассыпаются все правила показа
/// экрана — `mkdir` замигает чёрным, молча провалившаяся команда промолчит, а
/// панель перестанет перечитываться.
///
/// **Чем отличается от чужих решений.** `mc` подсовывает оболочке
/// `bash --init-file`, VS Code просит дописать строку в `.zshrc`. Мы ничего не
/// правим: уговор уходит в **уже запущенную** сессию первой же строкой и живёт
/// ровно столько, сколько она. Не подошёл — ничего не сломалось.
///
/// **На экране его не видно.** Метка — управляющая последовательность (OSC), а
/// не текст: разбор терминала съедает её целиком. Незнакомый код `xterm` отдаёт
/// наружу отдельным ходом (`Terminal.onPrivateOSC`) — оттуда её и берём.
/// Подробности — `docs/spec/single-shell-session.md`.
class ShellAgreement {
  ShellAgreement({String? nonce}) : nonce = nonce ?? _randomNonce();

  /// Своё число этой сессии.
  ///
  /// Метку может напечатать и чужая программа — `cat` на двоичном файле
  /// печатает что угодно. Совпадение случайного числа делает это невозможным
  /// на практике, а обходится в один разбор.
  final String nonce;

  /// Частный диапазон OSC и наше имя в нём.
  static const String _code = '777';
  static const String _name = 'fc';

  static String _randomNonce() {
    final random = Random();
    return List.generate(4, (_) => random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')).join();
  }

  /// Строка уговора для этой оболочки; пусто — такую мы уговаривать не умеем.
  ///
  /// Оболочку узнаём по имени того, чем её запустили. На своей машине это
  /// `$SHELL` или настройка, на сервере — что вернул `ShellHost`; не узнали —
  /// шлём общую строку, она разбирается сама.
  ///
  /// **Общая строка разбирается изнутри, а не снаружи** — потому что снаружи
  /// узнать нечем: на той стороне `ssh` мы про оболочку не знаем ничего.
  /// Ветка zsh спрятана в `eval` нарочно: массив `precmd_functions=(…)` для
  /// `dash` — ошибка разбора, а разбирает он всю строку целиком, ещё до того
  /// как выполнить хоть что-то из неё.
  String setupFor(String? shell) {
    final printf = "printf '\\e]$_code;$_name;$nonce;%s;%s\\a'";

    if (shell != null && shell.split('/').last == 'fish') {
      return 'function __fc_mark --on-event fish_prompt; $printf \$status "\$PWD"; end';
    }

    return [
      '__fc_mark() { $printf "\$1" "\$PWD"; }',
      'if [ -n "\$ZSH_VERSION" ]',
      "then eval '__fc_precmd() { __fc_mark \$?; }; precmd_functions=(__fc_precmd \$precmd_functions)'",
      'elif [ -n "\$BASH_VERSION" ]',
      // Своим впереди чужого: `$?` должен достаться нам не тронутым — чужой
      // `PROMPT_COMMAND` вправе запустить что угодно и сбить его.
      'then PROMPT_COMMAND=\'__fc_mark \$?\'"\${PROMPT_COMMAND:+; \$PROMPT_COMMAND}"',
      'fi',
    ].join('; ');
  }

  /// Разбирает то, что `xterm` отдал как незнакомый OSC; null — не наше.
  ///
  /// Каталог собирается обратно из хвоста: точка с запятой в имени каталога
  /// разрешена, и разбор OSC режет по ней наравне с настоящими разделителями.
  /// Поэтому каталог и стоит последним.
  ShellMark? parse(String code, List<String> parts) {
    if (code != _code || parts.length < 4 || parts[0] != _name || parts[1] != nonce) {
      return null;
    }
    final exitCode = int.tryParse(parts[2].trim());
    if (exitCode == null) {
      return null;
    }
    return ShellMark(exitCode: exitCode, directory: parts.sublist(3).join(';'));
  }
}
