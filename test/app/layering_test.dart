import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ядро не знает модули по именам.
///
/// Это не вкусовщина: как только ядро сошлётся на модуль напрямую, модуль
/// перестанет быть необязательным — а вся затея в том, что его можно убрать
/// из списка, и приложение соберётся.
void main() {
  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('модули упоминаются только в списке модулей', () {
    // Единственное место, которому положено знать имена: там список и лежит.
    const allowed = ['lib/bootstrap/app_modules.dart'];

    // Эти пакеты ядру знать положено, и ни один не модуль: три API объявляют
    // контракты — общий, ядра и интерфейса, — `fc_ui_kit` даёт то, чем рисуют,
    // `fc_platform` — то, что умеет только настоящая машина. Регистрировать в
    // них нечего, убрать их из списка нельзя, и необязательными они никогда не
    // были.
    //
    // `fc_platform` попал сюда не ради поблажки: подготовку окна `main.dart`
    // зовёт **до** того, как появятся модули и граф служб, и пока она лежала в
    // модуле локальной ФС, ядру приходилось знать модуль по имени.
    const libraries = [
      "package:fc_api/",
      "package:fc_core_api/",
      "package:fc_ui_api/",
      "package:fc_ui_kit/",
      "package:fc_platform/",
    ];

    final offenders = [
      for (final file in sources)
        if (!allowed.any(file.path.endsWith))
          for (final import in RegExp("import 'package:fc_[a-z_]+/").allMatches(file.readAsStringSync()))
            if (!libraries.any((library) => import[0]!.contains(library))) file.path,
    ];

    expect(offenders, isEmpty, reason: 'ядро знает только контракты и набор элементов интерфейса');
  });

  test('ядро пишется против API, а не против его внутренностей', () {
    // `package:fc_api/src/...` — обход барабана: так в ядро протекают
    // подробности, которые API не обещал. Проверяются все три пакета API.
    const internals = ["package:fc_api/src/", "package:fc_core_api/src/", "package:fc_ui_api/src/"];
    final offenders = [
      for (final file in sources)
        for (final internal in internals)
          if (file.readAsStringSync().contains(internal)) file.path,
    ];

    expect(offenders, isEmpty);
  });
}
