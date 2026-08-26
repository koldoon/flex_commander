import 'package:fc_api/fc_api.dart';

/// Что терминал помнит между запусками.
class TerminalSettings implements Serializable {
  TerminalSettings({this.shell = '', this.maxLines = 10000, List<String>? history}) : history = history ?? <String>[];

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

  /// История команд, старые впереди.
  List<String> history;

  @override
  void fromMap(Map<String, dynamic> m) {
    shell = extract(shell, m['shell']);
    maxLines = extract(maxLines, m['maxLines']);
    history = extractList<String>(m['history']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['shell'] = shell;
    m['maxLines'] = maxLines;
    m['history'] = history;
  }
}
