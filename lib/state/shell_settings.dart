import 'package:fc_api/fc_api.dart';

/// Что помнит о себе сама оболочка.
///
/// Своего модуля у ядра нет, а помнить есть что: раздел называется `fc.shell` и
/// живёт по тем же правилам, что и разделы модулей.
class ShellSettings implements Serializable {
  ShellSettings({
    this.allowElevatedWrites = true,
    this.useBuiltinExtensions = true,
    List<String>? compoundExtensions,
    List<String>? recentCommands,
  }) : compoundExtensions = compoundExtensions ?? <String>[],
       recentCommands = recentCommands ?? <String>[];

  /// Составные расширения, дописанные человеком: `cfg.json`, `story.tsx`.
  ///
  /// Идут **впереди** встроенных: своё можно поставить над общим, а не спорить
  /// с ним.
  List<String> compoundExtensions;

  /// Учитывать ли встроенный список (`tar.gz`, `spec.ts`, `min.js`…).
  bool useBuiltinExtensions;

  /// Предлагать ли запись от администратора там, где обычных прав не хватило.
  ///
  /// Выключенная — предложения нет вовсе, и отказ остаётся отказом. На общей
  /// машине это единственный честный ответ. Живёт здесь, а не у локальной ФС:
  /// повышение работает и на той стороне `ssh`, и настройка у него общая.
  bool allowElevatedWrites;

  /// Недавно запущенные команды, свежие впереди.
  ///
  /// Это состояние, а не выбор: в окне настроек его нет — как нет там истории
  /// команд и путей панелей.
  List<String> recentCommands;

  @override
  void fromMap(Map<String, dynamic> m) {
    allowElevatedWrites = extract(allowElevatedWrites, m['allowElevatedWrites']);
    useBuiltinExtensions = extract(useBuiltinExtensions, m['useBuiltinExtensions']);
    compoundExtensions = extractList<String>(m['compoundExtensions']);
    recentCommands = extractList<String>(m['recentCommands']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['allowElevatedWrites'] = allowElevatedWrites;
    m['useBuiltinExtensions'] = useBuiltinExtensions;
    m['compoundExtensions'] = compoundExtensions;
    m['recentCommands'] = recentCommands;
  }
}
