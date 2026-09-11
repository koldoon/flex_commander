import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Что окно команды помнит о себе между запусками.
///
/// Имена полей здесь — **внешний контракт**: они лежат в `settings.json`, и
/// файл, написанный прежней сборкой, обязан читаться новой
/// (`docs/spec/dialog-resize.md`, §3).
void main() {
  DialogState roundTrip(DialogState state) {
    final map = <String, dynamic>{};
    state.toMap(map);
    return DialogState()..fromMap(map);
  }

  test('размер и место переживают запись и чтение', () {
    final saved = roundTrip(DialogState(width: 700, height: 500, offsetX: -60, offsetY: 40));

    expect(saved.width, 700);
    expect(saved.height, 500);
    expect(saved.offsetX, -60);
    expect(saved.offsetY, 40);
  });

  test('нетронутое окно не пишет о себе ничего', () {
    final map = <String, dynamic>{};
    DialogState().toMap(map);

    expect(map, isEmpty, reason: 'ноль — это отсутствие записи, а не число');
    expect(DialogState().isEmpty, isTrue);
  });

  test('одно отодвинутое окно помнить стоит, даже если размер не трогали', () {
    final state = DialogState(offsetX: 0, offsetY: -90);

    expect(state.isEmpty, isFalse);
    expect(roundTrip(state).offsetY, -90);
  });

  test('файл прежней сборки читается: место просто не записано', () {
    final saved = DialogState()..fromMap({'width': 640.0, 'height': 480.0});

    expect(saved.width, 640);
    expect(saved.offsetX, 0);
    expect(saved.offsetY, 0);
  });

  test('мусор вместо числа — то же, что «не задано»', () {
    final saved = DialogState()..fromMap({'width': 'wide', 'offsetX': double.infinity, 'offsetY': 'no'});

    expect(saved.width, 0);
    expect(saved.offsetX, 0, reason: 'окно, уехавшее в бесконечность, не вернуть ничем');
    expect(saved.offsetY, 0);
  });
}
