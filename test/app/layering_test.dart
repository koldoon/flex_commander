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
    const allowed = 'lib/bootstrap/app_modules.dart';

    // Два пакета ядру знать положено, и оба — не модули: `fc_api` объявляет
    // контракты, `fc_ui_kit` даёт то, чем рисуют. Регистрировать в них нечего,
    // убрать их из списка нельзя, и необязательными они никогда не были.
    const libraries = ["package:fc_api/", "package:fc_ui_kit/"];

    final offenders = [
      for (final file in sources)
        if (!file.path.endsWith(allowed))
          for (final import in RegExp("import 'package:fc_[a-z_]+/").allMatches(file.readAsStringSync()))
            if (!libraries.any((library) => import[0]!.contains(library))) file.path,
    ];

    expect(offenders, isEmpty, reason: 'ядро знает только контракты и набор элементов интерфейса');
  });

  test('ядро пишется против API, а не против его внутренностей', () {
    // `package:fc_api/src/...` — обход барабана: так в ядро протекают
    // подробности, которые API не обещал.
    final offenders = [
      for (final file in sources)
        if (file.readAsStringSync().contains("package:fc_api/src/")) file.path,
    ];

    expect(offenders, isEmpty);
  });
}
