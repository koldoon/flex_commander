import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_ssh/fc_ssh.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Слияние вывода оболочки: в псевдотерминале поток один, а библиотека отдаёт
/// его двумя.
void main() {
  late StreamController<Uint8List> out;
  late StreamController<Uint8List> err;

  setUp(() {
    out = StreamController<Uint8List>();
    err = StreamController<Uint8List>();
  });

  test('оба потока идут в один и не спорят за него', () async {
    // Живой случай: первая версия звала `addStream` дважды и падала на
    // «Cannot add event while adding a stream» — терминал по ssh не
    // открывался вовсе.
    final merged = mergedOutput(out.stream, err.stream);
    final seen = <String>[];
    merged.listen((chunk) => seen.add(utf8.decode(chunk)));

    out.add(bytes('раз'));
    err.add(bytes('два'));
    out.add(bytes('три'));
    await pumpEventQueue();

    expect(seen, ['раз', 'два', 'три']);
  });

  test('поток кончается, когда кончились оба', () async {
    final merged = mergedOutput(out.stream, err.stream);
    var done = false;
    merged.listen(null, onDone: () => done = true);

    await out.close();
    await pumpEventQueue();
    expect(done, isFalse, reason: 'второй ещё жив — оболочка не кончилась');

    await err.close();
    await pumpEventQueue();
    expect(done, isTrue);
  });

  test('ошибка канала кончает поток, а не роняет приложение', () async {
    final merged = mergedOutput(out.stream, err.stream);
    var done = false;
    merged.listen(null, onDone: () => done = true);

    out.addError(StateError('канал оборван'));
    await err.close();
    await pumpEventQueue();

    // Показать ошибку канала в терминале нечем, а код возврата скажет точнее.
    expect(done, isTrue);
  });
}
