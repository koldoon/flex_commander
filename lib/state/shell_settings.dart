import 'package:fc_api/fc_api.dart';

/// Что помнит о себе сама оболочка.
///
/// Своего модуля у ядра нет, а помнить есть что: раздел называется `fc.shell` и
/// живёт по тем же правилам, что и разделы модулей.
class ShellSettings implements Serializable {
  ShellSettings({List<String>? recentCommands}) : recentCommands = recentCommands ?? <String>[];

  /// Недавно запущенные команды, свежие впереди.
  ///
  /// Это состояние, а не выбор: в окне настроек его нет — как нет там истории
  /// команд и путей панелей.
  List<String> recentCommands;

  @override
  void fromMap(Map<String, dynamic> m) => recentCommands = extractList<String>(m['recentCommands']);

  @override
  void toMap(Map<String, dynamic> m) => m['recentCommands'] = recentCommands;
}
