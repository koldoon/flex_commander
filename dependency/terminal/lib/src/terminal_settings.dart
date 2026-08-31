import 'package:fc_api/fc_api.dart';

/// Что терминал помнит между запусками.
class TerminalSettings implements Serializable {
  TerminalSettings({
    this.shell = '',
    this.maxLines = defaultMaxLines,
    this.typingGoesToLine = false,
    this.runExecutables = true,
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
    history = extractList<String>(m['history']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['shell'] = shell;
    m['maxLines'] = maxLines;
    m['typingGoesToLine'] = typingGoesToLine;
    m['runExecutables'] = runExecutables;
    m['history'] = history;
  }
}
