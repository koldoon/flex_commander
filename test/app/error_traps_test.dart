import 'package:flex_commander/bootstrap/error_traps.dart';
import 'package:flex_commander/state/error_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ловушки: единственное место, где решается, увидит ли человек поломку.
void main() {
  late ErrorController errors;
  late ErrorTraps traps;

  setUp(() {
    errors = ErrorController(environment: const {});
    traps = ErrorTraps();
  });

  test('пойманное до появления приложения не теряется', () {
    // Поломка при запуске — тоже поломка: показать её некому, но как только
    // окно появится, она там окажется.
    traps.handle(StateError('сломалось при запуске'), StackTrace.fromString('#0 boot'));
    expect(traps.pendingEarly, 1);

    traps.attach(errors);

    expect(errors.pending, 1);
    expect(errors.current?.message, contains('сломалось при запуске'));
    expect(traps.pendingEarly, 0, reason: 'накопленное отдано и больше не держится');
  });

  test('после подключения ошибка идёт прямо к сборщику', () {
    traps.attach(errors);

    traps.handle(ArgumentError('плохой довод'), null, 'Copying');

    expect(errors.pending, 1);
    expect(errors.current?.context, 'Copying');
  });

  test('в журнал уходит всё пойманное', () {
    final logged = <Object>[];
    ErrorTraps(log: (error, stack) => logged.add(error))
      ..attach(errors)
      ..handle(StateError('раз'), null);

    expect(logged, hasLength(1));
  });

  group('глобальные ловушки', () {
    late FlutterExceptionHandler? previousFlutter;

    setUp(() => previousFlutter = FlutterError.onError);
    tearDown(() => FlutterError.onError = previousFlutter);

    test('ошибка каркаса доходит до сборщика', () {
      traps
        ..install()
        ..attach(errors);

      // Так о своих бедах сообщает Flutter: сборка, раскладка, отрисовка.
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('отрисовка не удалась'),
          stack: StackTrace.fromString('#0 paint'),
          context: ErrorDescription('building FileTable'),
        ),
      );

      expect(errors.current?.message, contains('отрисовка не удалась'));
      expect(errors.current?.context, contains('building FileTable'));
    });
  });
}
