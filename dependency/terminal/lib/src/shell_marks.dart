import 'dart:math';

/// О чём оболочка отметилась.
enum ShellMarkKind {
  /// Печатает приглашение: прошлая команда кончилась, вот её код и каталог.
  prompt,

  /// Сейчас выполнит набранное.
  ///
  /// Нужна ровно для одного — отличить **вывод команды** от отражения самой
  /// команды. Оболочка отражает набранное, как отражала бы в любом терминале,
  /// и без этой метки «молча и успешно» не определить: вывод есть всегда.
  running,
}

/// Что оболочка сообщила о себе.
///
/// Приходит не после команды, а перед приглашением и перед запуском:
/// приглашение и запуск — единственное, что оболочка печатает предсказуемо.
class ShellMark {
  const ShellMark({required this.kind, this.exitCode = 0, this.directory = ''});

  final ShellMarkKind kind;

  /// Код возврата последней команды; у [ShellMarkKind.running] бессмыслен.
  final int exitCode;

  /// Где оболочка оказалась. Пусто — не сказала.
  final String directory;

  @override
  String toString() => 'ShellMark(${kind.name}, $exitCode, $directory)';
}

/// Уговор с оболочкой: отмечаться дважды — перед запуском команды и перед
/// приглашением, кодом возврата и каталогом.
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

  /// О чём метка: приглашение или запуск.
  static const String _prompt = 'p';
  static const String _running = 'r';

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
    final prompt = "printf '\\e]$_code;$_name;$nonce;$_prompt;%s;%s\\a'";
    final running = "\\e]$_code;$_name;$nonce;$_running\\a";

    if (shell != null && shell.split('/').last == 'fish') {
      return [
        'function __fc_prompt --on-event fish_prompt; $prompt \$status "\$PWD"; end',
        "function __fc_running --on-event fish_preexec; printf '$running'; end",
      ].join('; ');
    }

    return [
      '__fc_mark() { $prompt "\$1" "\$PWD"; }',
      'if [ -n "\$ZSH_VERSION" ]',
      "then eval '__fc_precmd() { __fc_mark \$?; }; __fc_preexec() { printf \"$running\"; }; "
          "precmd_functions=(__fc_precmd \$precmd_functions); preexec_functions=(__fc_preexec \$preexec_functions)'",
      'elif [ -n "\$BASH_VERSION" ]',
      // Своим впереди чужого: `$?` должен достаться нам не тронутым — чужой
      // `PROMPT_COMMAND` вправе запустить что угодно и сбить его.
      //
      // `PS0` печатается перед запуском — после того, как оболочка отразила
      // набранное. Старый `bash` (3.2, тот, что стоит в macOS) его не знает:
      // метки о запуске не будет, и вывод команды не отличить от её отражения.
      // Не ломается — показывается чаще, чем нужно.
      'then PROMPT_COMMAND=\'__fc_mark \$?\'"\${PROMPT_COMMAND:+; \$PROMPT_COMMAND}"; PS0="$running\$PS0"',
      'fi',
    ].join('; ');
  }

  /// Разбирает то, что `xterm` отдал как незнакомый OSC; null — не наше.
  ///
  /// Каталог собирается обратно из хвоста: точка с запятой в имени каталога
  /// разрешена, и разбор OSC режет по ней наравне с настоящими разделителями.
  /// Поэтому каталог и стоит последним.
  ShellMark? parse(String code, List<String> parts) {
    if (code != _code || parts.length < 3 || parts[0] != _name || parts[1] != nonce) {
      return null;
    }
    switch (parts[2]) {
      case _running:
        return const ShellMark(kind: ShellMarkKind.running);
      case _prompt when parts.length >= 5:
        final exitCode = int.tryParse(parts[3].trim());
        return exitCode == null
            ? null
            : ShellMark(kind: ShellMarkKind.prompt, exitCode: exitCode, directory: parts.sublist(4).join(';'));
      default:
        return null;
    }
  }
}
