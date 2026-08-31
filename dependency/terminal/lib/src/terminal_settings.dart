import 'package:fc_api/fc_api.dart';

/// Что терминал помнит между запусками.
class TerminalSettings implements Serializable {
  TerminalSettings({
    this.shell = '',
    this.maxLines = defaultMaxLines,
    this.typingGoesToLine = false,
    this.runExecutables = true,
    this.afterCommand = defaultAfterCommand,
    List<String>? history,
  }) : history = history ?? <String>[];

  /// Сколько строк держится в прокрутке терминала.
  ///
  /// Имя, а не число в конструкторе: то же умолчание называет схема настроек,
  /// и расходиться им нельзя.
  static const int defaultMaxLines = 10000;

  /// Сколько команд помнится. Больше сотни никто не пролистывает, а файл
  /// настроек — не журнал.
  static const int historyLimit = 100;

  /// Экран уходит по концу команды.
  static const String hideAfterCommand = 'hide';

  /// Экран ждёт клавиши.
  static const String waitAfterCommand = 'wait';

  /// Ждать клавиши: так было всегда, и человек, читавший вывод, его не теряет.
  static const String defaultAfterCommand = waitAfterCommand;

  /// Что делать с экраном, когда команда закончилась.
  ///
  /// Правильного ответа нет: одному вывод нужен ровно на то мгновение, пока
  /// команда идёт, другому — прочитать его спокойно. На **провалившуюся**
  /// команду не действует: код возврата — единственное, о чём точно нужно
  /// сказать, и убирать его с глаз по таймеру нельзя.
  String afterCommand;

  /// Чем запускать команды; пусто — тем, чем работает человек (`$SHELL`).
  ///
  /// Настройка нужна не ради выбора любимой оболочки, а ради предсказуемости:
  /// на машине, где `$SHELL` смотрит на что-нибудь неожиданное, поправить это
  /// должно быть где.
  String shell;

  /// Сколько строк вывода помнит терминал.
  int maxLines;

  /// Печать в панели уходит в командную строку — повадка `mc`.
  ///
  /// Названо по поведению, а не по чужой программе: «печать уходит в строку»
  /// объясняет себя, а «режим mc» требует знать `mc`. Умолчание — выключено:
  /// переход к имени по первой букве привычен тем, кто пришёл из Total
  /// Commander и Far.
  bool typingGoesToLine;

  /// `Enter` на файле с битом `+x` запускает его, а не отдаёт системе.
  ///
  /// Умолчание — включено: ради этого настройка и заведена
  /// (`spec/run-executables.md`). Выключенная возвращает `Enter` системе и
  /// больше ничего не меняет — она нужна тому, кто держит рядом с документами
  /// исполняемые скрипты и открывает их в редакторе.
  bool runExecutables;

  /// История команд, старые впереди.
  List<String> history;

  @override
  void fromMap(Map<String, dynamic> m) {
    shell = extract(shell, m['shell']);
    maxLines = extract(maxLines, m['maxLines']);
    typingGoesToLine = extract(typingGoesToLine, m['typingGoesToLine']);
    runExecutables = extract(runExecutables, m['runExecutables']);
    afterCommand = extract(afterCommand, m['afterCommand']);
    history = extractList<String>(m['history']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['shell'] = shell;
    m['maxLines'] = maxLines;
    m['typingGoesToLine'] = typingGoesToLine;
    m['runExecutables'] = runExecutables;
    m['afterCommand'] = afterCommand;
    m['history'] = history;
  }
}
