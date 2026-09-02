import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// У ядра нет экрана, а у его API — ещё и платформы.
///
/// `dart:io` живёт в модулях: источник может стоять над архивом, над сетью или
/// над памятью, и API, потянувшее платформу, потянет её за собой всюду.
/// Виджетов же здесь нет по самой сути разделения — рисует другая сторона
/// (`docs/spec/client-server.md`, §3).
///
/// Проверяется грепом по исходникам: запретить импорт иначе нечем, а тест
/// ловит нарушение в тот же день, когда оно появилось.
void main() {
  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('в API ядра нет dart:io', () {
    final offenders = [
      for (final file in sources)
        if (file.readAsStringSync().contains("import 'dart:io'")) file.path,
    ];

    expect(offenders, isEmpty, reason: 'платформа живёт в модулях, а не в API');
  });

  test('ядро не знает про экран', () {
    const forbidden = [
      'package:flutter/widgets.dart',
      'package:flutter/material.dart',
      'package:flutter/services.dart',
      'package:fc_ui_api/',
      'package:fc_ui_kit/',
    ];

    final offenders = [
      for (final file in sources)
        for (final import in forbidden)
          if (file.readAsStringSync().contains("import '$import")) '${file.path}: $import',
    ];

    expect(offenders, isEmpty, reason: 'рисует другая сторона: ядро её не видит');
  });

  test('в контракте работ нет приложения, областей и панелей', () {
    // Живое состояние читает команда — до запуска, — а работе отдаёт снимок
    // параметрами. Стоит приложению просочиться в контракт работы, и фоновое
    // копирование сломается в тот день, когда панель выйдет из архива.
    const contracts = ['lib/src/tree/operation_params.dart'];
    const forbidden = ['Application', 'ApplicationView', 'Panel'];

    final code = [
      for (final contract in contracts)
        for (final line in File(contract).readAsLinesSync())
          if (!line.trimLeft().startsWith('///') && !line.trimLeft().startsWith('//')) line,
    ].join('\n');

    final offenders = [
      for (final name in forbidden)
        if (RegExp('\\b$name\\b').hasMatch(code)) name,
    ];

    expect(offenders, isEmpty, reason: 'работа получает снимок параметрами, а не живое приложение');
  });
}
