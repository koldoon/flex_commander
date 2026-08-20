import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/state/error_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сборщик того, что никто не поймал.
void main() {
  late FakeClipboard clipboard;
  late ErrorController errors;

  setUp(() {
    clipboard = FakeClipboard();
    errors = ErrorController(
      clipboard: clipboard,
      version: '1.2.3',
      // Окружение задаётся, а не берётся у машины: иначе тест зависел бы от
      // того, где его запустили.
      environment: const {'Platform': 'test'},
    );
  });

  test('пока ничего не сломалось, показывать нечего', () {
    expect(errors.current, isNull);
    expect(errors.pending, 0);
  });

  test('ошибка становится показанной', () {
    errors.report(StateError('нет такого'), StackTrace.fromString('#0 main'), 'Packing archive');

    expect(errors.current?.type, 'StateError');
    expect(errors.current?.message, contains('нет такого'));
    expect(errors.current?.context, 'Packing archive');
    expect(errors.pending, 1);
  });

  test('очередь: закрыли одну — показана следующая', () {
    errors
      ..report(StateError('первая'))
      ..report(ArgumentError('вторая'));
    expect(errors.pending, 2);

    errors.dismiss();

    expect(errors.current?.message, contains('вторая'));
    expect(errors.pending, 1);

    errors.dismiss();

    expect(errors.current, isNull);
  });

  test('одинаковые подряд склеиваются в одну со счётчиком', () {
    // Ошибка отрисовки приходит на каждый кадр: без склейки окон было бы
    // столько же, сколько кадров.
    final stack = StackTrace.fromString('#0 paint');
    for (var i = 0; i < 5; i++) {
      errors.report(StateError('то же самое'), stack);
    }

    expect(errors.pending, 1);
    expect(errors.current?.repeats, 5);
  });

  test('разные ошибки не склеиваются', () {
    errors
      ..report(StateError('одна'), StackTrace.fromString('#0 a'))
      ..report(StateError('другая'), StackTrace.fromString('#0 b'));

    expect(errors.pending, 2);
  });

  test('очередь не растёт бесконечно', () {
    for (var i = 0; i < ErrorController.maxPending * 2; i++) {
      errors.report(StateError('ошибка $i'), StackTrace.fromString('#0 place$i'));
    }

    expect(errors.pending, ErrorController.maxPending);
  });

  group('отчёт', () {
    test('копируется целиком: тип, сообщение, стек и окружение', () async {
      errors.report(StateError('нет такого'), StackTrace.fromString('#0 main'), 'Packing archive');

      expect(await errors.copyReport(), isTrue);

      final report = clipboard.text!;
      expect(report, contains('StateError'));
      expect(report, contains('нет такого'));
      expect(report, contains('#0 main'));
      expect(report, contains('While: Packing archive'));
      expect(report, contains('Version: 1.2.3'));
      expect(report, contains('Platform: test'));
    });

    test('копировать нечего — и говорится об этом', () async {
      expect(await errors.copyReport(), isFalse);
      expect(clipboard.text, isNull);
    });

    test('повторы попадают в отчёт', () async {
      errors
        ..report(StateError('то же'), StackTrace.fromString('#0 a'))
        ..report(StateError('то же'), StackTrace.fromString('#0 a'));

      await errors.copyReport();

      expect(clipboard.text, contains('Repeats: 2'));
    });
  });

  test('в журнал уходит всё, даже если окно закроют не глядя', () {
    final logged = <ErrorReport>[];
    final controller = ErrorController(onLog: logged.add);

    controller.report(StateError('раз'));
    controller.report(StateError('два'));

    expect(logged, hasLength(2));
  });
}
