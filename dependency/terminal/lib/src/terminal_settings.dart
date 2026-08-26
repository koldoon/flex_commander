import 'package:fc_api/fc_api.dart';

/// Что терминал помнит между запусками.
class TerminalSettings implements Serializable {
  TerminalSettings({this.shell = '', this.maxLines = 10000, this.typingGoesToLine = false, List<String>? history})
    : history = history ?? <String>[];

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

  /// История команд, старые впереди.
  List<String> history;

  @override
  void fromMap(Map<String, dynamic> m) {
    shell = extract(shell, m['shell']);
    maxLines = extract(maxLines, m['maxLines']);
    typingGoesToLine = extract(typingGoesToLine, m['typingGoesToLine']);
    history = extractList<String>(m['history']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['shell'] = shell;
    m['maxLines'] = maxLines;
    m['typingGoesToLine'] = typingGoesToLine;
    m['history'] = history;
  }
}
