import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сообщения разбора переводятся — и это стережёт сборка, а не внимательность.
///
/// Доктринальный тест приложения сюда не достаёт: он ищет `tr('…')` в коде, а
/// эти строки попадают в перевод **значением** — `said.tr(error.message)`.
/// Забытая строка ушла бы к человеку по-английски и ничего бы не уронила.
void main() {
  test('у каждого сообщения разбора есть русский перевод', () {
    final sources = Directory(
      'lib/src',
    ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'));

    final messages = <String>{};
    for (final file in sources) {
      final text = file.readAsStringSync();
      for (final match in RegExp(r"MermaidError\(\s*[^,]+,\s*'([^']+)'").allMatches(text)) {
        messages.add(match.group(1)!);
      }
    }

    expect(messages, isNotEmpty, reason: 'сообщения должны находиться регуляркой, иначе сторож бесполезен');

    final dictionary = File('lib/src/mermaid_module.dart').readAsStringSync();
    final missing = [
      for (final message in messages)
        if (!dictionary.contains("'$message':")) message,
    ];

    expect(missing, isEmpty, reason: 'эти сообщения уйдут человеку по-английски');
  });
}
