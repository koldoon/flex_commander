import 'package:fc_api/fc_api.dart';

import 'shell_command.dart';

/// Последний токен строки, разобранный для дополнения.
///
/// Разбор отделён от всего остального нарочно: это чистая работа со строкой, и
/// проверять её надо без приложения, панели и провайдера — вариантов у неё
/// больше, чем у всего дополнения вместе взятого.
class CompletionToken {
  const CompletionToken({
    required this.start,
    required this.end,
    required this.directory,
    required this.prefix,
    required this.quote,
  });

  /// Границы токена в строке: сюда же вставляется дополненное.
  ///
  /// [start] указывает на начало токена **вместе** с открывающей кавычкой:
  /// заменяется он целиком, а кавычку дописывает тот, кто вставляет.
  final int start;
  final int end;

  /// Каталог, в котором искать; пусто — каталог панели.
  ///
  /// Путь как набрали, без разбора `~`: домашний каталог знает провайдер, а не
  /// разбор строки.
  final String directory;

  /// Начало имени, по которому отбирать.
  final String prefix;

  /// Кавычка, которой токен открыт; пусто — токен без кавычек.
  final String quote;

  /// Токен пуст — строка кончается пробелом или пуста вовсе.
  bool get isEmpty => directory.isEmpty && prefix.isEmpty;

  /// Разбирает строку до курсора.
  ///
  /// Токеном считается всё от последнего **неэкранированного** пробела вне
  /// кавычек до курсора. От курсора, а не от конца строки: поправить середину
  /// команды — обычное дело, и дополнять в этот момент надо то, что под
  /// курсором.
  factory CompletionToken.parse(String line, int cursor) {
    final at = cursor.clamp(0, line.length);
    var start = 0;
    var quote = '';
    var quoteStart = -1;

    for (var i = 0; i < at; i++) {
      final char = line[i];
      if (char == r'\') {
        // Экранированное следом идёт как есть — в том числе пробел.
        i++;
        continue;
      }
      if (quote.isNotEmpty) {
        if (char == quote) {
          quote = '';
          quoteStart = -1;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        quoteStart = i;
        continue;
      }
      if (char == ' ' || char == '\t') {
        start = i + 1;
      }
    }

    // Кавычка, открытая внутри токена, началом токена и остаётся: закрыть её
    // придётся при вставке.
    if (quote.isNotEmpty && quoteStart >= start) {
      start = quoteStart;
    }

    final raw = line.substring(start, at);
    final value = _unescape(quote.isEmpty ? raw : raw.substring(1));
    final slash = value.lastIndexOf('/');

    return CompletionToken(
      start: start,
      end: at,
      directory: slash < 0 ? '' : value.substring(0, slash + 1),
      prefix: slash < 0 ? value : value.substring(slash + 1),
      quote: quote,
    );
  }

  /// Снимает экранирование: `my\ file` — это одно имя, а не два.
  static String _unescape(String value) {
    if (!value.contains(r'\')) {
      return value;
    }
    final result = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (value[i] == r'\' && i + 1 < value.length) {
        result.write(value[++i]);
        continue;
      }
      result.write(value[i]);
    }
    return result.toString();
  }

  @override
  String toString() => 'CompletionToken($start..$end, dir=$directory, prefix=$prefix, quote=$quote)';
}

/// Общее начало у всех строк списка; пусто — общего нет.
String commonPrefix(List<String> values) {
  if (values.isEmpty) {
    return '';
  }
  var prefix = values.first;
  for (final value in values.skip(1)) {
    var length = 0;
    while (length < prefix.length && length < value.length && prefix[length] == value[length]) {
      length++;
    }
    prefix = prefix.substring(0, length);
    if (prefix.isEmpty) {
      break;
    }
  }
  return prefix;
}

/// Что можно подставить: имя объекта и то, каталог ли это.
class CompletionCandidate {
  const CompletionCandidate(this.name, {required this.isDirectory});

  final String name;
  final bool isDirectory;

  /// Как это выглядит в строке: каталог с косой чертой, чтобы следующий `Tab`
  /// пошёл внутрь него.
  String get insertion => isDirectory ? '$name/' : name;

  @override
  String toString() => insertion;
}

/// Подбор кандидатов для токена.
///
/// Отдельно от команды: команда — прототип, а это чистая работа с деревом,
/// которую хочется проверять без приложения.
class CompletionSource {
  const CompletionSource({required this.provider, required this.directory});

  /// Источник панели. Он же знает свой домашний каталог — `~` разбирает не
  /// строка, а он.
  final TreeProvider provider;

  /// Каталог панели: от него считается всё, что набрано без косой черты в
  /// начале.
  final String directory;

  /// Кандидаты, отсортированные по имени; пусто — подставить нечего.
  ///
  /// Скрытые объекты попадают в список, **только если** начало имени
  /// начинается с точки: `s` не должен предлагать `.ssh`, а `.s` — обязан.
  Future<List<CompletionCandidate>> candidates(CompletionToken token) async {
    final node = await provider.resolvePath().run(pathOf(token.directory));
    if (node is! DirectoryNode) {
      return const [];
    }

    // `listChildren`, а не `getDirectoryListing`: тот складывает список в узел
    // и подменил бы то, что показывает панель, а нам нужны просто имена — со
    // скрытыми и без «..».
    final children = await provider.listChildren(node);
    final hidden = token.prefix.startsWith('.');

    final found = [
      for (final child in children)
        if (child.name.startsWith(token.prefix) && (hidden || !child.name.startsWith('.')))
          CompletionCandidate(child.name, isDirectory: child is DirectoryNode),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return found;
  }

  /// Путь каталога, в котором искать.
  ///
  /// `~` разбирается здесь, потому что домашний каталог — свойство источника:
  /// у сервера он свой, и подставлять локальный было бы враньём.
  String pathOf(String tokenDirectory) {
    if (tokenDirectory.isEmpty) {
      return directory;
    }
    if (tokenDirectory == '~' || tokenDirectory == '~/') {
      return provider.homePath;
    }
    if (tokenDirectory.startsWith('~/')) {
      return _join(provider.homePath, tokenDirectory.substring(2));
    }
    if (tokenDirectory.startsWith('/')) {
      return tokenDirectory;
    }
    return _join(directory, tokenDirectory);
  }

  static String _join(String base, String rest) {
    final left = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final right = rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
    return right.isEmpty ? left : '$left/$right';
  }
}

/// Начатое дополнение: кандидаты и то, куда их подставлять.
///
/// Живёт между нажатиями `Tab`, поэтому и хранится в строке, а не в команде:
/// команда — прототип, у неё состояния нет.
class CompletionRun {
  CompletionRun({required this.start, required this.directory, required this.quote, required this.candidates});

  /// Начало токена в строке — вместе с открывающей кавычкой.
  final int start;

  /// Приставка каталога, как её набрали: подставляется обратно вместе с именем.
  final String directory;

  /// Кавычка, которой токен открыт.
  final String quote;

  final List<CompletionCandidate> candidates;

  /// Который кандидат подставлен; -1 — перебор ещё не начинали.
  int index = -1;

  /// Куда дошла вставка: отсюда и до [start] заменяется на следующего.
  int end = 0;

  /// Строка целиком после нашей вставки.
  ///
  /// Перебор обрывается, как только строку тронули чем-нибудь ещё: `Tab` после
  /// правки — это новый подбор, а не следующий кандидат.
  String text = '';

  bool get hasChoice => candidates.length > 1;

  bool matches(String current) => current == text;

  /// Следующий по кругу; [forward] false — предыдущий.
  CompletionCandidate step({required bool forward}) {
    final count = candidates.length;
    index = forward ? (index + 1) % count : (index <= 0 ? count - 1 : index - 1);
    return candidates[index];
  }
}

/// Строка для оболочки: путь в кавычках, но так, чтобы `~` остался `~`.
///
/// `'~/my file'` оболочка домашним каталогом не считает — кавычки отменяют
/// подстановку. Поэтому обрамляется только то, что после тильды.
String quotePath(String value) {
  if (value.startsWith('~/')) {
    return '~/${ShellCommand.quote(value.substring(2))}';
  }
  return ShellCommand.quote(value);
}
