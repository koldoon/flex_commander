import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// API не знает ни файловой системы, ни процессов, ни окон.
///
/// Это не вкусовщина: провайдер может стоять над архивом, над сетью или над
/// памятью, а команда — выполняться в тесте без всякой платформы. Стоит
/// `dart:io` появиться в API, и любой модуль потянет за собой платформу,
/// на которой он, может быть, и не работает.
///
/// Проверяется грепом по исходникам: запретить импорт иначе нечем, а тест
/// ловит нарушение в тот же день, когда оно появилось.
void main() {
  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('в API нет dart:io', () {
    final offenders = [
      for (final file in sources)
        if (file.readAsStringSync().contains("import 'dart:io'")) file.path,
    ];

    expect(offenders, isEmpty, reason: 'платформа живёт в модулях, а не в API');
  });

  test('модели и фреймворк не тянут виджеты', () {
    // Флаттер в API есть, и это осознанно: команда описывает своё окно
    // виджетом, тема — ThemeExtension, подписка — Listenable. Но виджеты
    // и клавиатура допустимы только там, где без них нельзя: интерфейс и
    // действия. Модель, дерево, операции и фреймворк остаются чистыми —
    // ими можно пользоваться и без экрана.
    const uiOnly = ['lib/src/ui/', 'lib/src/commands/app_command.dart', 'lib/src/commands/key_combination.dart'];
    const forbidden = [
      "package:flutter/widgets.dart",
      "package:flutter/material.dart",
      "package:flutter/services.dart",
    ];

    final offenders = [
      for (final file in sources)
        if (!uiOnly.any(file.path.contains))
          for (final import in forbidden)
            if (file.readAsStringSync().contains("import '$import'")) '${file.path}: $import',
    ];

    expect(offenders, isEmpty, reason: 'модель и фреймворк должны работать без экрана');
  });
}
