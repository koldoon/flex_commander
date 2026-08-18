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

    final offenders = [
      for (final file in sources)
        if (!file.path.endsWith(allowed))
          if (file.readAsStringSync().contains("import 'package:fc_") &&
              !file.readAsStringSync().contains("import 'package:fc_api/"))
            file.path,
    ];

    expect(offenders, isEmpty, reason: 'ядро должно знать только fc_api');
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
