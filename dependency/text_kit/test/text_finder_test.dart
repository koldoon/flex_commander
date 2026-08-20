import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Поиск по показанному тексту.
///
/// Тесты асинхронные: библиотека считает совпадения в изоляте, и `search`
/// дожидается его — иначе команда сообщала бы счёт до того, как он посчитан.
void main() {
  const String text = '''
void main() {
  final answer = 42;
  print(answer);
  print('Answer');
}''';

  late FcTextFinder finder;

  setUp(() => finder = FcTextFinder(CodeLineEditingController.fromText(text)));
  tearDown(() => finder.dispose());

  test('находит все совпадения и встаёт на первое', () async {
    final int count = await finder.search('answer');

    expect(count, 3);
    expect(finder.matchCount, 3);
    expect(finder.currentIndex, 1);
    expect(finder.pattern, 'answer');
  });

  test('следующее и предыдущее ходят по кругу', () async {
    await finder.search('print');
    expect(finder.currentIndex, 1);

    expect(finder.next(), isTrue);
    expect(finder.currentIndex, 2);

    // По кругу: после последнего снова первое.
    finder.next();
    expect(finder.currentIndex, 1);

    finder.previous();
    expect(finder.currentIndex, 2);
  });

  test('с учётом регистра совпадений меньше', () async {
    expect(await finder.search('answer', caseSensitive: true), 2);
    expect(await finder.search('Answer', caseSensitive: true), 1);
    expect(await finder.search('Answer'), 3);
  });

  test('регулярное выражение', () async {
    expect(await finder.search(r'print\(\w+\)', regex: true), 1);
    expect(await finder.search(r'\d+', regex: true), 1);
  });

  test('найденное выделено — в просмотрщике курсора не видно', () async {
    await finder.search('42');

    expect(finder.controller.selectedText, '42');
  });

  test('пустая строка ничего не ищет', () async {
    expect(await finder.search(''), 0);
    expect(finder.matchCount, 0);
  });

  test('не нашлось — ходить не по чему', () async {
    expect(await finder.search('такого тут нет'), 0);
    expect(finder.next(), isFalse);
    expect(finder.previous(), isFalse);
    expect(finder.currentIndex, 0);
  });

  test('подсветку можно снять', () async {
    await finder.search('print');
    expect(finder.matchCount, 2);

    finder.clear();

    expect(finder.matchCount, 0);
  });
}
