/// Отбор и веса палитры команд — без единого виджета.
///
/// Вынесено отдельно потому, что случаев здесь больше, чем во всём окне:
/// проверять их надо коротким тестом, а не сборкой приложения.
library;

/// Что нашлось в одной строке списка.
class PaletteMatch implements Comparable<PaletteMatch> {
  const PaletteMatch({required this.score, required this.labelHits, required this.length});

  /// Вес совпадения; больше — выше в списке.
  final double score;

  /// Какие буквы названия совпали — их подсвечивают.
  ///
  /// Без подсветки непонятно, почему строка вообще нашлась: `cpf` в `Copy File`
  /// со стороны выглядит случайностью.
  final List<int> labelHits;

  /// Длина названия: при равном весе выигрывает короткое — `Copy` перед
  /// `Copy path to clipboard`.
  final int length;

  @override
  int compareTo(PaletteMatch other) {
    final byScore = other.score.compareTo(score);
    return byScore != 0 ? byScore : length.compareTo(other.length);
  }
}

/// Ищет буквы запроса **по порядку, но не подряд**: `cpf` находит `Copy File`.
///
/// Регистр не важен. Пустой запрос подходит всему — палитра при этом остаётся
/// каталогом, а не пустым окном.
///
/// Вес складывается из трёх правил, и порядок между ними важнее самих чисел:
/// с начала слова весит больше, чем с середины; подряд — больше, чем
/// вразбивку; при равном весе выигрывает короткое название (это уже в
/// [PaletteMatch.compareTo]).
///
/// [keywords] — слова, которых в названии нет, а искать по ним будут: `gz` для
/// «Mk Tar», умеющей `.tar.gz`, и название модуля у любой команды палитры
/// (`term` должен находить команды терминала). Весят они вдвое меньше названия:
/// название всё же ближе к делу, чем синоним или то, кем команда принесена.
/// Подсвечивать в них нечего — в списке их не видно, и подсветка указывала бы
/// на буквы, которых там нет.
PaletteMatch? matchCommand(String query, {required String label, Iterable<String> keywords = const []}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return PaletteMatch(score: 0, labelHits: const [], length: label.length);
  }

  final byLabel = _match(trimmed, label);
  if (byLabel != null) {
    return PaletteMatch(score: byLabel.score, labelHits: byLabel.hits, length: label.length);
  }

  // Лучший из синонимов, а не первый совпавший: их у команды несколько, и
  // порядок объявления — не мера того, насколько слово подошло.
  double? best;
  for (final keyword in keywords) {
    final byKeyword = _match(trimmed, keyword);
    if (byKeyword != null && (best == null || byKeyword.score > best)) {
      best = byKeyword.score;
    }
  }
  if (best != null) {
    return PaletteMatch(score: best / 2, labelHits: const [], length: label.length);
  }

  return null;
}

/// Совпадение в одной строке: вес и места букв.
class _Hit {
  const _Hit(this.score, this.hits);

  final double score;
  final List<int> hits;
}

/// Жадный поиск слева направо.
///
/// Жадный — то есть первая подходящая буква и берётся. Изредка это даёт не
/// лучшее выравнивание (`co` в `Cancel copy` встанет на `C` и `o` первого
/// слова), но перебор всех выравниваний стоил бы дороже, чем выигрывает, а
/// надбавка за начало слова и так вытягивает разумный порядок.
_Hit? _match(String query, String text) {
  final needle = query.toLowerCase();
  final haystack = text.toLowerCase();
  final hits = <int>[];
  var score = 0.0;
  var at = 0;
  var previous = -2;

  for (final char in needle.split('')) {
    if (char == ' ') {
      continue;
    }
    final found = haystack.indexOf(char, at);
    if (found < 0) {
      return null;
    }

    score += _matched;
    // С начала слова — вес больше: `set` в `Settings` лучше, чем в `Reset`.
    if (found == 0 || _isBoundary(haystack[found - 1])) {
      score += _atWordStart;
    } else if (found == previous + 1) {
      // Подряд — лучше, чем вразбивку.
      score += _inRow;
    }

    // Разрыв — в минус, и первый пропущенный дороже следующих.
    //
    // Без этого «с начала слова» перебивало бы «подряд»: `opy` находился бы в
    // `Order picked yesterday` лучше, чем в `Copy`, — три начала слова весят
    // больше двух букв подряд. Штраф ставит это на место, а сами числа взяты по
    // образцу `fzf`: важны не они, а порядок между правилами.

    final skipped = previous < 0 ? found : found - previous - 1;
    if (skipped > 0) {
      score -= _firstSkipped + (skipped - 1) * _nextSkipped;
    }

    hits.add(found);
    previous = found;
    at = found + 1;
  }

  return _Hit(score, hits);
}

/// Вес одной совпавшей буквы и надбавки к нему.
///
/// Числа по образцу `fzf`: важны не они сами, а порядок между правилами.
const double _matched = 16;
const double _atWordStart = 8;
const double _inRow = 8;
const double _firstSkipped = 3;
const double _nextSkipped = 1;

bool _isBoundary(String char) => char == ' ' || char == '-' || char == '.' || char == '/' || char == '_';
