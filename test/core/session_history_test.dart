import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/core/session_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// История переходов сессии: порядок шагов и место, где мы в нём стоим
/// (`docs/spec/session-history.md`).
void main() {
  int limit = 50;
  SessionHistory history() => SessionHistory(limit: () => limit);

  PathStep step(String path, [String cursor = '']) => PathStep(path: path, cursor: cursor);

  /// Пути шагов по порядку — так проверки читаются целиком.
  List<String> pathsOf(SessionHistory h) => [for (final s in h.steps) s.path];

  setUp(() => limit = 50);

  test('пустой истории идти некуда', () {
    final h = history();

    expect(h.canGoBack, isFalse);
    expect(h.canGoForward, isFalse);
    expect(h.current, isNull);
    expect(h.back(), isNull);
    expect(h.forward(), isNull);
  });

  test('прошли три каталога — назад дважды возвращает в первый', () {
    final h =
        history()
          ..visit(step('/a'))
          ..visit(step('/b'))
          ..visit(step('/c'));

    expect(h.back()?.path, '/b');
    expect(h.back()?.path, '/a');
    expect(h.canGoBack, isFalse, reason: 'дальше первого шага идти некуда');
    expect(h.canGoForward, isTrue);
  });

  test('назад возвращает курсор туда, где он стоял', () {
    final h =
        history()
          ..visit(step('/a', 'notes.txt'))
          ..visit(step('/a/deep'));

    expect(h.back(), step('/a', 'notes.txt'));
  });

  test('шаг назад сам в историю не пишется', () {
    final h =
        history()
          ..visit(step('/a'))
          ..visit(step('/b'));
    h.back();

    expect(pathsOf(h), ['/a', '/b'], reason: 'возврат добавил шаг — «назад» не кончится никогда');
    expect(h.current?.path, '/a');
  });

  test('новый переход после возврата обрезает «вперёд»', () {
    final h =
        history()
          ..visit(step('/a'))
          ..visit(step('/b'))
          ..visit(step('/c'));
    h.back();
    h.back();
    h.visit(step('/d'));

    expect(pathsOf(h), ['/a', '/d']);
    expect(h.canGoForward, isFalse);
  });

  test('то же место подряд шага не добавляет, но курсор в нём обновляет', () {
    final h = history()..visit(step('/a', 'one.txt'));

    expect(h.visit(step('/a', 'one.txt')), isFalse, reason: 'ничего не изменилось');
    expect(h.visit(step('/a', 'two.txt')), isTrue);
    expect(pathsOf(h), ['/a']);
    expect(h.current?.cursor, 'two.txt');
  });

  test('шаг без пути не записывается вовсе', () {
    final h = history();

    expect(h.visit(step('')), isFalse);
    expect(h.steps, isEmpty);
  });

  test('курсор нынешнего шага обновляется на ходу', () {
    final h = history()..visit(step('/a', 'one.txt'));
    h.noteCursor('three.txt');
    h.visit(step('/b'));

    expect(h.back(), step('/a', 'three.txt'), reason: 'вернулись не туда, где стояли перед уходом');
  });

  test('прыжок к шагу «вперёд» не обрезает', () {
    final h =
        history()
          ..visit(step('/a'))
          ..visit(step('/b'))
          ..visit(step('/c'))
          ..visit(step('/d'));

    expect(h.goTo(1)?.path, '/b');
    expect(pathsOf(h), ['/a', '/b', '/c', '/d'], reason: 'прыжок — ход по истории, а не новый переход');
    expect(h.forward()?.path, '/c');
    expect(h.goTo(1)?.path, '/b');
    expect(h.goTo(1), isNull, reason: 'стоим тут же — идти некуда');
    expect(h.goTo(9), isNull);
  });

  test('предел вытесняет самый старый шаг', () {
    limit = 3;
    final h =
        history()
          ..visit(step('/a'))
          ..visit(step('/b'))
          ..visit(step('/c'))
          ..visit(step('/d'));

    expect(pathsOf(h), ['/b', '/c', '/d']);
    expect(h.current?.path, '/d', reason: 'стоим там же, куда пришли');
    expect(h.back()?.path, '/c');
  });

  test('уменьшенный предел действует со следующего перехода', () {
    final h =
        history()
          ..visit(step('/a'))
          ..visit(step('/b'))
          ..visit(step('/c'));
    limit = 2;
    h.visit(step('/d'));

    expect(pathsOf(h), ['/c', '/d']);
  });

  test('поднятая из настроек история продолжается с того же места', () {
    final h = SessionHistory(steps: [step('/a'), step('/b'), step('/c')], index: 1, limit: () => limit);

    expect(h.current?.path, '/b');
    expect(h.canGoBack, isTrue);
    expect(h.canGoForward, isTrue);
    expect(h.forward()?.path, '/c');
  });

  test('сбившийся номер приводит к последнему шагу, а не роняет разбор', () {
    final h = SessionHistory(steps: [step('/a'), step('/b')], index: 42, limit: () => limit);

    expect(h.current?.path, '/b');
  });

  test('история отдаёт себя настройкам ровно такой, какой живёт', () {
    final h =
        history()
          ..visit(step('/a', 'one.txt'))
          ..visit(step('/b'));
    h.back();

    final saved = h.saved;
    expect(saved.steps, [step('/a', 'one.txt'), step('/b')]);
    expect(saved.index, 0);
  });
}
