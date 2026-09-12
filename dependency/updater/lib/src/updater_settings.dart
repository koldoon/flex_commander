import 'package:fc_api/fc_api.dart';

/// Что модуль обновления помнит между запусками.
class UpdaterSettings implements Serializable {
  UpdaterSettings({this.checkAtStartup = true, this.lastCheck = '', this.postponed = ''});

  /// Спрашивать GitHub при запуске.
  ///
  /// Включено: приложение, о новой версии которого никто не знает, обновляют
  /// раз в полгода и по случаю.
  bool checkAtStartup;

  /// Когда спрашивали в прошлый раз — `ISO 8601`; пусто — ещё ни разу.
  ///
  /// **Состояние, а не настройка:** в окне настроек его нет, как нет там
  /// истории команд и путей панелей.
  String lastCheck;

  /// Версия, про которую сказали «Позже».
  ///
  /// Откладывает до следующего запуска, а не навсегда: забыть о выпуске совсем
  /// — это выключить проверку, и для этого есть флажок
  /// (`docs/spec/self-update.md`, §8).
  String postponed;

  /// Пора ли спрашивать снова: не чаще раза в сутки.
  bool dueAt(DateTime now, {Duration every = const Duration(days: 1)}) {
    if (!checkAtStartup) {
      return false;
    }
    final last = DateTime.tryParse(lastCheck);
    // Времени последней проверки нет или оно из будущего (перевели часы) —
    // спрашиваем: ждать сутки после чужой ошибки незачем.
    if (last == null || last.isAfter(now)) {
      return true;
    }
    return now.difference(last) >= every;
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['checkAtStartup'] = checkAtStartup;
    if (lastCheck.isNotEmpty) {
      m['lastCheck'] = lastCheck;
    }
    if (postponed.isNotEmpty) {
      m['postponed'] = postponed;
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    checkAtStartup = extract(checkAtStartup, m['checkAtStartup']);
    lastCheck = extract(lastCheck, m['lastCheck']);
    postponed = extract(postponed, m['postponed']);
  }
}
