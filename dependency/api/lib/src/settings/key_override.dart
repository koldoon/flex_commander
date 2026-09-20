import '../serialization.dart';

/// Переназначенная клавиша: у какой привязки какая теперь
/// (`docs/spec/key-bindings.md`, §4).
///
/// **Привязка опознаётся командой и прежней комбинацией.** Своего
/// идентификатора у неё нет, и заводить его незачем: сменится умолчание в новом
/// выпуске — переназначение просто отпадёт, и человек увидит новое умолчание.
/// Это честнее, чем переназначение, повисшее на клавише, которой больше нет.
///
/// Комбинации — строками, теми же, какими их разбирают (`KeyCombination.parse`)
/// и какими они записаны в документации: `Alt-Cmd-C`. Порядок модификаторов в
/// них закреплён, поэтому один и тот же выбор всегда даёт одну и ту же строку.
class KeyOverride implements Serializable {
  KeyOverride({this.command = '', this.was = '', this.now = ''});

  /// Команда привязки (`AppCommand.id`).
  String command;

  /// Клавиша, которая стояла по умолчанию.
  String was;

  /// Что стоит теперь; пусто — клавиши нет вовсе.
  String now;

  /// Годится ли запись к делу: без команды и прежней клавиши опознавать нечего.
  bool get isSane => command.isNotEmpty && was.isNotEmpty && was != now;

  @override
  void toMap(Map<String, dynamic> m) {
    m['command'] = command;
    m['was'] = was;
    // Пустая строка пишется тоже: «клавиши нет» — это выбор человека, а не
    // отсутствие записи.
    m['now'] = now;
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    command = extract(command, m['command']);
    was = extract(was, m['was']);
    now = extract(now, m['now']);
  }

  @override
  String toString() => '$command: $was → ${now.isEmpty ? '—' : now}';
}
