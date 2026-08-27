import 'package:fc_api/fc_api.dart';

/// Что модуль навигации помнит между запусками.
class NavigationSettings implements Serializable {
  NavigationSettings({this.recentPathsLimit = defaultLimit, List<String>? recentPaths})
    : recentPaths = recentPaths ?? <String>[];

  /// Сколько адресов помнится по умолчанию.
  ///
  /// Правильного числа тут нет: тому, кто ходит по трём каталогам, и пяти
  /// много, а тому, кто держит в голове полсотни серверов, тридцати мало.
  /// Поэтому предел — настройка, а это лишь её умолчание.
  static const int defaultLimit = 30;

  /// Куда уже успешно ходили, свежие впереди.
  ///
  /// Это состояние, а не выбор: в окне настроек его нет — как нет там истории
  /// команд и путей панелей.
  List<String> recentPaths;

  int recentPathsLimit;

  /// Запоминает успешно открытый адрес.
  ///
  /// Повтор поднимается наверх, а не ложится вторым: список коротких походов по
  /// одним и тем же местам иначе вытеснил бы сам себя.
  void remember(String address) {
    final value = address.trim();
    if (value.isEmpty) {
      return;
    }
    recentPaths
      ..remove(value)
      ..insert(0, value);
    _trim();
  }

  /// Что показать в окне: не больше предела, каким бы длинным ни был список.
  ///
  /// Уменьшенный предел действует **сразу на показ**, а сам список подрезается
  /// при следующей записи: так уменьшение видно немедленно, а лишней записи в
  /// файл на каждое движение настройки не случается.
  List<String> get shownPaths => recentPaths.take(recentPathsLimit.clamp(0, recentPaths.length)).toList();

  void _trim() {
    if (recentPaths.length > recentPathsLimit) {
      recentPaths.removeRange(recentPathsLimit, recentPaths.length);
    }
  }

  @override
  void fromMap(Map<String, dynamic> m) {
    recentPathsLimit = extract(recentPathsLimit, m['recentPathsLimit']);
    recentPaths = extractList<String>(m['recentPaths']);
  }

  @override
  void toMap(Map<String, dynamic> m) {
    m['recentPathsLimit'] = recentPathsLimit;
    m['recentPaths'] = recentPaths;
  }
}

/// Адрес без пароля.
///
/// Пароль из адреса забирается один раз и уходит в `Credentials`
/// (`providers.md`); в историю ему тем более не место — файл настроек лежит
/// открытым текстом.
///
/// Обычный путь (`/etc`, `~/Downloads`) возвращается как есть: разбирать в нём
/// нечего.
String addressWithoutPassword(String address) {
  if (!address.contains('://') || !address.contains('@')) {
    return address;
  }

  final parsed = Uri.tryParse(address);
  if (parsed == null || parsed.userInfo.isEmpty || !parsed.userInfo.contains(':')) {
    return address;
  }

  final user = parsed.userInfo.split(':').first;
  return parsed.replace(userInfo: user).toString();
}
