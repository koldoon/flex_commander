import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Накопитель: работа делается, когда события кончились
/// (`docs/spec/directory-watch.md`, §4).
void main() {
  const quiet = Duration(milliseconds: 40);
  const atMost = Duration(milliseconds: 200);

  late int runs;
  late Settle settle;

  Settle make({Future<void> Function()? action}) =>
      Settle(action ?? () async => runs++, quiet: () => quiet, atMost: () => atMost);

  setUp(() => runs = 0);
  tearDown(() => settle.cancel());

  test('первое событие сразу не срабатывает', () async {
    settle = make();
    settle();

    await Future<void>.delayed(quiet ~/ 2);
    expect(runs, 0, reason: 'событие — повод, а не приказ');

    await Future<void>.delayed(quiet);
    expect(runs, 1);
  });

  test('пачка событий сводится к одному вызову', () async {
    settle = make();
    // Пачка короче предела ожидания: иначе сработать посреди неё — законно, и
    // проверяется это отдельно, следующим тестом.
    for (var i = 0; i < 8; i++) {
      settle();
      await Future<void>.delayed(quiet ~/ 4);
    }
    await Future<void>.delayed(quiet * 2);

    expect(runs, 1, reason: 'восемь событий — одно чтение');
  });

  test('долгая пачка срабатывает по пределу ожидания, а не в конце', () async {
    settle = make();
    // События идут не переставая: окно тишины не наступает никогда.
    final noise = Stream<void>.periodic(quiet ~/ 3).take(30).listen((_) => settle());
    await Future<void>.delayed(atMost * 2);
    await noise.cancel();

    expect(runs, greaterThanOrEqualTo(1), reason: 'список не замирает до конца бури');

    await Future<void>.delayed(quiet * 2);
  });

  test('события во время работы дают ровно один следующий вызов', () async {
    var started = 0;
    final held = <void Function()>[];
    settle = make(
      action: () {
        started++;
        final done = Completer<void>();
        held.add(done.complete);
        return done.future;
      },
    );

    settle();
    await Future<void>.delayed(quiet * 2);
    expect(started, 1, reason: 'работа пошла');

    // Пока она идёт — десяток событий.
    for (var i = 0; i < 10; i++) {
      settle();
    }
    expect(started, 1, reason: 'два чтения одного каталога разом не нужны никому');

    held.single();
    await Future<void>.delayed(quiet * 3);

    expect(started, 2, reason: 'и ровно одно следующее');
  });

  test('отмена забывает накопленное и не оставляет отсчёта', () async {
    settle = make();
    settle();
    expect(settle.pending, isTrue);

    settle.cancel();
    expect(settle.pending, isFalse);

    await Future<void>.delayed(quiet * 3);
    expect(runs, 0);
  });
}
