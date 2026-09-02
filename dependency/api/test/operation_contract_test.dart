import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Работа не знает про приложение.
///
/// Живое состояние читает команда — до запуска, — а работе отдаёт снимок
/// параметрами. Стоит приложению просочиться в контракт работы, и фоновое
/// копирование сломается в тот день, когда панель выйдет из архива: работа
/// пойдёт спрашивать «где мы сейчас» у того, кто уже ушёл.
///
/// Проверяется грепом, как и чистота API от `dart:io`: запретить упоминание
/// иначе нечем, а тест ловит нарушение в тот же день, когда оно появилось.
void main() {
  test('в контракте работ нет приложения, областей и панелей', () {
    // Реестр работ — другое дело: он как раз знает, под какой панелью
    // показывать полоску. Проверяется контракт самой работы: сама Operation и
    // типы её параметров — то, из чего работа узнаёт, что ей делать.
    // Параметры работ уехали в API ядра — там же и проверяются: тот же
    // греп лежит в `fc_core_api/test/operation_contract_test.dart`.
    const contracts = ['lib/src/async/async_operation.dart'];
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

    expect(offenders, isEmpty, reason: 'работа получает снимок параметрами, а не доступ к приложению');
  });
}
