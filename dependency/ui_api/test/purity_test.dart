import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// API интерфейса не видит API ядра — и это проверяет сборка, а не уговор.
///
/// В этом и был весь смысл разреза на три пакета: «где проходит граница» должно
/// иметь один ответ, и отвечать на него должен компилятор. Фронтовая половина
/// модуля физически не может взять `TreeProvider` — не потому, что так
/// договорились, а потому, что его здесь нет (`docs/spec/client-server.md`, §3).
///
/// Проверка живёт здесь, а не в приложении: пакет отвечает за себя сам, и
/// нарушение видно в тот же день, когда появилось.
void main() {
  test('fc_core_api нет среди зависимостей', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = pubspec.where((line) => line.trimRight().endsWith('fc_core_api:'));

    expect(declared, isEmpty, reason: 'дерево и провайдеры — та сторона границы; сюда они не ходят');
  });

  test('в исходниках его тоже нет', () {
    // Зависимости может не быть, а импорт — быть: пакет, притянутый через
    // соседний, компилируется точно так же. Поэтому смотрим и в исходники.
    final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

    final offenders = [
      for (final file in sources)
        if (file.readAsStringSync().contains('package:fc_core_api/')) file.path,
    ];

    expect(offenders, isEmpty, reason: 'ядровые типы в контрактах экрана не появляются');
  });
}
