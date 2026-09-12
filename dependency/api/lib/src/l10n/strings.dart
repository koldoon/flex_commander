import 'package:flutter/foundation.dart';

import '../values/fs_error.dart';

/// Три формы русского множественного числа.
///
/// Именованные, а не по порядку: `(one: '{n} файл', few: '{n} файла',
/// many: '{n} файлов')` читается, а тройка строк подряд — нет.
typedef PluralForms = ({String one, String few, String many});

/// Строки интерфейса на языке человека.
///
/// Спецификация — `docs/spec/localization.md`.
///
/// **Ключ перевода — сама английская строка.** Она остаётся там, где её
/// показывают, и она же служит запасным значением: пока перевода нет, `tr`
/// возвращает то, что стояло раньше. Поэтому английских словарей не бывает —
/// английский написан в коде.
///
/// [Listenable] — как и у оформления: язык меняется на лету, и интерфейс
/// перестраивается тем же способом, что при смене темы.
abstract interface class Strings implements Listenable {
  /// `en` или `ru`.
  String get language;

  /// Перевод строки.
  ///
  /// Подстановки — по имени: `tr('Copy «{name}»', args: {'name': node.name})`.
  /// По имени, а не по порядку: в переводе слова меняются местами.
  ///
  /// [context] разводит одинаковые тексты с разным переводом: `tr('Open',
  /// context: 'viewer')`. Ищется только целиком — перевода с оговоркой нет,
  /// значит английский, а не перевод строки без оговорки.
  String tr(String text, {Map<String, Object?> args, String? context});

  /// Множественное число.
  ///
  /// Английский называет обе формы на месте, русский берёт три из словаря по
  /// ключу [other]. `{n}` подставляется само.
  String plural(int count, {required String one, required String other, Map<String, Object?> args, String? context});

  /// Ошибка дерева словами.
  ///
  /// [FsError] — значение, служб у него нет, и переводить себя ему нечем:
  /// `FsError.message` остаётся английским и уходит в журнал, а человеку
  /// ошибку показывают отсюда.
  String describe(FsError error);
}

/// Собранные переводы: то, что объявили модули.
///
/// Пространство одно на приложение, а не на модуль: `Cancel` во всех окнах
/// переводится одинаково, и двадцать словарей ради двадцати одинаковых записей
/// заводить незачем. Два разных перевода одного ключа — ошибка сборки
/// ([add] бросает), и ровно для этого случая есть оговорка `context`.
class StringsRegistry extends ChangeNotifier implements Strings {
  StringsRegistry({this.languageSource});

  /// Язык, на котором приложение говорит, пока не сказано иного. Он же —
  /// язык, написанный в коде.
  static const String defaultLanguage = 'en';

  /// Языки, на которые приложение переведено. Английский сюда не входит: он
  /// не перевод, а исходник.
  static const List<String> translations = ['ru'];

  /// Все языки, между которыми можно выбирать.
  static const List<String> languages = [defaultLanguage, ...translations];

  /// Откуда брать язык — способ узнать, а не значение: его правят в настройках,
  /// и следующая же надпись должна прийти на новом. Ставит сборка, когда
  /// настройки прочитаны; null — английский, как в коде.
  ///
  /// Словари собираются раньше, чем появляются настройки, поэтому поле, а не
  /// довод конструктора.
  String Function()? languageSource;

  @override
  String get language {
    final value = languageSource?.call() ?? defaultLanguage;
    return languages.contains(value) ? value : defaultLanguage;
  }

  /// Язык сменился — перерисоваться.
  ///
  /// Зовёт тот, кто настройку и поменял: реестр за файлом настроек не следит,
  /// а знать о смене должен весь экран разом.
  void refresh() => notifyListeners();

  /// Язык → ключ → перевод.
  final Map<String, Map<String, String>> _words = {};

  /// Язык → ключ формы `other` → три формы.
  final Map<String, Map<String, PluralForms>> _plurals = {};

  /// Что объявил модуль. Ключи — английские строки, какими они написаны в коде.
  void add(String language, Map<String, String> words) {
    final known = _words.putIfAbsent(language, () => {});
    for (final entry in words.entries) {
      final was = known[entry.key];
      if (was != null && was != entry.value) {
        // Молчаливая победа последнего означала бы, что перевод зависит от
        // порядка модулей в списке.
        throw StateError('Два перевода «${entry.key}» на $language: «$was» и «${entry.value}»');
      }
      known[entry.key] = entry.value;
    }
  }

  /// То же для множественных форм.
  void addPlurals(String language, Map<String, PluralForms> forms) {
    final known = _plurals.putIfAbsent(language, () => {});
    for (final entry in forms.entries) {
      final was = known[entry.key];
      if (was != null && was != entry.value) {
        throw StateError('Две формы «${entry.key}» на $language');
      }
      known[entry.key] = entry.value;
    }
  }

  /// Все объявленные переводы этого языка. Нужно доктринальному тесту: он
  /// сверяет словари с тем, что встречается в исходниках.
  Map<String, String> wordsOf(String language) => Map.unmodifiable(_words[language] ?? const {});

  Map<String, PluralForms> pluralsOf(String language) => Map.unmodifiable(_plurals[language] ?? const {});

  @override
  String tr(String text, {Map<String, Object?> args = const {}, String? context}) =>
      _fill(_lookup(text, context) ?? text, args);

  @override
  String plural(
    int count, {
    required String one,
    required String other,
    Map<String, Object?> args = const {},
    String? context,
  }) {
    final forms = _plurals[language]?[_key(other, context)];
    final template = forms == null ? (count == 1 ? one : other) : pickRussian(count, forms);
    return _fill(template, {'n': count, ...args});
  }

  @override
  String describe(FsError error) {
    final path = {'path': error.path};
    return switch (error.kind) {
      FsErrorKind.notFound => tr('Not found: {path}', args: path),
      FsErrorKind.permissionDenied => tr('Permission denied: {path}', args: path),
      FsErrorKind.notADirectory => tr('Not a directory: {path}', args: path),
      FsErrorKind.alreadyExists => tr('Already exists: {path}', args: path),
      FsErrorKind.invalidName => tr('Invalid name: {path}', args: path),
      FsErrorKind.targetInsideSource => tr('Cannot copy a directory into itself: {path}', args: path),
      FsErrorKind.notSupported => tr('Not supported: {path}', args: path),
      FsErrorKind.unknownUser => tr('No such user or group: {path}', args: path),
      FsErrorKind.unsupportedScheme => tr('Protocol {path} is not supported', args: path),
      FsErrorKind.invalidAddress => tr('Wrong URI: {path}', args: path),
      FsErrorKind.io => tr('I/O error: {path}', args: path),
      FsErrorKind.cannotConnect => tr('Cannot connect: {path}', args: path),
    };
  }

  String? _lookup(String text, String? context) => _words[language]?[_key(text, context)];

  static String _key(String text, String? context) => context == null ? text : '$context|$text';

  static String _fill(String template, Map<String, Object?> args) {
    if (args.isEmpty) {
      return template;
    }
    var result = template;
    for (final entry in args.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  /// Какая из трёх форм подходит числу.
  ///
  /// Правило русского известно и не меняется, поэтому оно здесь, а не в
  /// библиотеке правил на все языки мира.
  static String pickRussian(int count, PluralForms forms) {
    final n = count.abs();
    final tens = n % 100;
    final ones = n % 10;
    if (ones == 1 && tens != 11) {
      return forms.one;
    }
    if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) {
      return forms.few;
    }
    return forms.many;
  }
}
