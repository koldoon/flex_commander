/// Версия сборки: три числа, как их пишет тег выпуска.
///
/// Сравнивается **числами, а не строками**: `0.0.9` меньше `0.0.10`, хотя по
/// алфавиту наоборот. Ошибка эта тихая — обновление просто перестало бы
/// предлагаться на десятом выпуске подряд.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  /// Разбирает `v0.0.72`, `0.0.72` и `0.0.72+128`; null — это не версия.
  ///
  /// Буква `v` впереди — от тега (`v0.0.72`), хвост после `+` — номер сборки:
  /// он приходит счётчиком прогонов и к старшинству версий отношения не имеет.
  static AppVersion? parse(String text) {
    var value = text.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    if (plus >= 0) {
      value = value.substring(0, plus);
    }

    final parts = value.split('.');
    if (parts.isEmpty || parts.length > 3) {
      return null;
    }
    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      // Отрицательных версий не бывает, а «0.0.1-beta» — это не наш случай:
      // предвыпуски мы не берём вовсе (`docs/spec/self-update.md`, §10).
      if (number == null || number < 0) {
        return null;
      }
      numbers.add(number);
    }
    // Недостающие звенья — нули: `1.0` это `1.0.0`.
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) {
      return byMajor;
    }
    final byMinor = minor.compareTo(other.minor);
    return byMinor != 0 ? byMinor : patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.major == major && other.minor == minor && other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
