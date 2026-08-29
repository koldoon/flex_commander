/// Маска имён: `*.dart;*.md`.
///
/// Один движок на всё приложение — пометку, окраску строк и будущий поиск: три
/// разных ответа на вопрос «что такое `*.txt`» хуже, чем любой один. Поэтому
/// маска и живёт в API, а не в модуле, которому понадобилась первым.
///
/// Из подстановок только две — `*` и `?`. Ни диапазонов `[a-z]`, ни фигурных
/// скобок: в именах файлов человек ждёт `*.txt`, а не выражение.
class FileMask {
  const FileMask._(this._include, this._exclude);

  /// Разбирает список образцов через `;`.
  ///
  /// Образец с `!` в начале **исключает**, и исключения применяются
  /// последними, независимо от порядка: `*;!*.bak` и `!*.bak;*` значат одно и
  /// то же — «всё, кроме `.bak`». Иначе строку пришлось бы читать как
  /// программу.
  factory FileMask.parse(String patterns) {
    final include = <RegExp>[];
    final exclude = <RegExp>[];

    for (final raw in patterns.split(';')) {
      final pattern = raw.trim();
      if (pattern.isEmpty) {
        continue;
      }
      if (pattern.startsWith('!')) {
        final rest = pattern.substring(1).trim();
        if (rest.isNotEmpty) {
          exclude.add(_regExpOf(rest));
        }
        continue;
      }
      include.add(_regExpOf(pattern));
    }

    return FileMask._(include, exclude);
  }

  /// Маска, не совпадающая ни с чем: пустая строка образцов.
  static final FileMask none = FileMask.parse('');

  final List<RegExp> _include;
  final List<RegExp> _exclude;

  /// Есть ли в маске хоть один образец. Пустая не совпадает ни с чем — в том
  /// числе поэтому её и стоит отличать от `*`.
  bool get isEmpty => _include.isEmpty && _exclude.isEmpty;

  /// Подходит ли имя.
  ///
  /// Имя целиком, вместе с расширением, и одинаково у файлов и каталогов:
  /// `*.d` совпадёт и с каталогом `src.d`. Правило про расширение
  /// (`FileNode.extension`) здесь ни при чём — маска смотрит на имя, а не на
  /// то, что приложение считает расширением: `*.gitignore` совпадает с
  /// `.gitignore`, хотя расширения у того нет.
  bool matches(String name) {
    if (_include.isEmpty) {
      return false;
    }
    if (!_include.any((pattern) => pattern.hasMatch(name))) {
      return false;
    }
    return !_exclude.any((pattern) => pattern.hasMatch(name));
  }

  /// Образец в выражение: `*` — сколько угодно любых символов, `?` — ровно
  /// один, всё остальное как есть.
  ///
  /// Регистр не важен: на macOS файловая система по умолчанию его не различает,
  /// и маска, которая различает, удивляла бы.
  static RegExp _regExpOf(String pattern) {
    final buffer = StringBuffer('^');
    for (final char in pattern.split('')) {
      switch (char) {
        case '*':
          buffer.write('.*');
        case '?':
          buffer.write('.');
        default:
          buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }
}
