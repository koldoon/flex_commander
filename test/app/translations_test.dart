import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/backend_registrations.dart';
import 'package:flex_commander/bootstrap/frontend_registrations.dart';
import 'package:flex_commander/bootstrap/registrations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Файлы, которые ищут строки, а не показывают их.
///
/// Здесь `tr` и `plural` **объявлены**, и находить их собственные упоминания
/// значило бы требовать перевода для слова «text».
const _definitions = [
  'dependency/api/lib/src/l10n/strings.dart',
  'dependency/ui_api/lib/src/commands/app_command.dart',
];

/// Чужой код, живущий в репозитории копией, и подставки для прогона: их строки
/// человек не увидит никогда.
const _foreign = ['dependency/re_editor/', 'dependency/test_kit/'];

/// Вызов `tr('…')` или `plural(…, other: '…')` в исходниках.
///
/// Перед `tr` не должно быть буквы — иначе в улов попали бы `substr(` и
/// подобные; точка перед ним, наоборот, обычна: строки спрашивают у службы.
final _trCall = RegExp(r"(?<![A-Za-z0-9_$])tr\(\s*'((?:[^'\\]|\\.)*)'");
final _pluralOther = RegExp(r"other:\s*'((?:[^'\\]|\\.)*)'");

/// Название модуля: оно видно в оглавлении настроек и в справке, а переводит
/// его тот, кто показывает, — у модуля служб нет. В коде это обычный литерал,
/// и найти его иначе нечем.
final _moduleTitle = RegExp(r"String get title => '((?:[^'\\]|\\.)*)'");

/// Ключ, собранный из литерала с интерполяцией: перевести его нельзя вовсе.
final _interpolated = RegExp(r"(?<![A-Za-z0-9_$])(?:tr|plural)\(\s*'[^']*\$");

List<File> _sources() {
  final roots = <Directory>[Directory('lib')];
  for (final package in Directory('dependency').listSync().whereType<Directory>()) {
    final sources = Directory('${package.path}/lib');
    if (sources.existsSync()) {
      roots.add(sources);
    }
  }

  return [
    for (final root in roots)
      ...root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !_definitions.any(file.path.endsWith))
          .where((file) => !_foreign.any(file.path.contains)),
  ];
}

/// Все ключи, которых код просит у реестра строк.
Set<String> _keysInSources() {
  final keys = <String>{};
  for (final file in _sources()) {
    final source = file.readAsStringSync();
    for (final match in _trCall.allMatches(source)) {
      keys.add(match.group(1)!);
    }
    for (final match in _pluralOther.allMatches(source)) {
      keys.add(match.group(1)!);
    }
    for (final match in _moduleTitle.allMatches(source)) {
      keys.add(match.group(1)!);
    }
  }
  return keys;
}

/// Переводы, собранные так же, как их собирает сборка приложения.
StringsRegistry _declared() {
  final frontend = FrontendRegistrations(LazyServices())..installAll(appModules().whereType<FcFrontendModule>());
  final backend = BackendRegistrations(LazyServices())..installAll(appModules().whereType<FcBackendModule>());
  final all = StringsRegistry();
  for (final side in [frontend.translations, backend.translations]) {
    all.add('ru', side.wordsOf('ru'));
    all.addPlurals('ru', side.pluralsOf('ru'));
  }
  return all;
}

/// Перевод есть у каждой строки, которую показывают.
///
/// Проверяется грепом по исходникам — тем же приёмом, что и чистота ядра
/// (`core_api/test/purity_test.dart`): иначе новая строка тихо осталась бы
/// английской, а заметили бы это на чужом экране
/// (`docs/spec/localization.md`, §13).
void main() {
  test('у каждой строки в коде есть русский перевод', () {
    final declared = _declared();
    final words = declared.wordsOf('ru');
    final plurals = declared.pluralsOf('ru');

    /// Оговорка входит в ключ, а искать её разбором вызова — гадание: хватает
    /// того, что перевод объявлен хоть с какой-то оговоркой.
    bool translated(String key) =>
        words.containsKey(key) ||
        plurals.containsKey(key) ||
        words.keys.any((declared) => declared.endsWith('|$key')) ||
        plurals.keys.any((declared) => declared.endsWith('|$key'));

    final missing = _keysInSources().where((key) => !translated(key)).toList()..sort();

    expect(missing, isEmpty, reason: 'непереведённое: ${missing.join(', ')}');
  });

  test('ключ не собирается подстановкой', () {
    final offenders = [
      for (final file in _sources())
        if (_interpolated.hasMatch(file.readAsStringSync())) file.path,
    ];

    // Ключ у каждого запуска был бы свой, и перевести его нельзя вовсе:
    // значения передаются через `args`.
    expect(offenders, isEmpty, reason: 'ключ перевода — литерал, значения идут через args');
  });

  test('в словарях нет строк, которых больше нет в коде', () {
    final declared = _declared();
    final used = _keysInSources();

    String withoutContext(String key) {
      final bar = key.indexOf('|');
      return bar < 0 ? key : key.substring(bar + 1);
    }

    final stale = [
      for (final key in [...declared.wordsOf('ru').keys, ...declared.pluralsOf('ru').keys])
        if (!used.contains(withoutContext(key))) key,
    ]..sort();

    expect(stale, isEmpty, reason: 'перевод есть, а строки нет: ${stale.join(', ')}');
  });
}
