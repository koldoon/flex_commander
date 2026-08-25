import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskOperation', () {
    test('возвращает результат и завершается', () async {
      final op = TaskOperation<int>((op) async => 42);

      expect(await op.result, 42);
      expect(op.state, OperationState.complete);
      expect(op.state.isFinished, isTrue);
    });

    test('ошибка тела попадает в результат', () async {
      final op = TaskOperation<int>((op) async => throw StateError('boom'));

      await expectLater(op.result, throwsA(isA<StateError>()));
      expect(op.state, OperationState.error);
    });

    test('отмена завершает операцию ошибкой OperationCanceled', () async {
      final started = Completer<void>();
      final op = TaskOperation<int>((op) async {
        started.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        op.checkCanceled();
        return 1;
      });

      await started.future;
      op.cancel();

      await expectLater(op.result, throwsA(isA<OperationCanceled>()));
      expect(op.state, OperationState.canceled);
    });

    test('результат отменённой операции не доходит до вызывающего', () async {
      final op = TaskOperation<int>((op) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 1;
      });

      op.cancel();
      await expectLater(op.result, throwsA(isA<OperationCanceled>()));

      // Тело успевает досчитать уже после отмены — состояние не должно меняться.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(op.state, OperationState.canceled);
    });

    test('повторная отмена ничего не ломает', () async {
      final op = TaskOperation<int>((op) async => 1);
      await op.result;

      op.cancel();
      expect(op.state, OperationState.complete);
    });

    test('прогресс доходит до подписчика', () async {
      final reported = <String>[];
      late TaskOperation<void> op;

      op = TaskOperation<void>((operation) async {
        // Даём подписчику встать до первого сообщения.
        await Future<void>.delayed(Duration.zero);
        operation.report(const OperationProgress(message: 'step 1'));
        operation.report(const OperationProgress(percent: 1, message: 'step 2'));
      });
      op.progress.listen((event) => reported.add(event.message));

      await op.result;
      await Future<void>.delayed(Duration.zero);

      expect(reported, ['step 1', 'step 2']);
    });
  });

  group('вопросы пользователю', () {
    test('ответ подписчика возвращается в тело операции', () async {
      late TaskOperation<String> op;

      op = TaskOperation<String>((operation) async {
        await Future<void>.delayed(Duration.zero);
        final answer = await operation.ask(
          OperationRequest(
            message: 'Overwrite file?',
            options: const [OperationRequestOption.overwrite, OperationRequestOption.skip],
            enterOption: OperationRequestOption.skip,
          ),
        );
        return answer.id;
      });
      op.requests.listen((request) => request.respond(OperationRequestOption.skip));

      expect(await op.result, 'skip');
    });

    test('без подписчиков применяется вариант по умолчанию', () async {
      final op = TaskOperation<String>((operation) async {
        final answer = await operation.ask(
          OperationRequest(
            message: 'Overwrite file?',
            options: const [OperationRequestOption.overwrite, OperationRequestOption.cancel],
            enterOption: OperationRequestOption.cancel,
          ),
        );
        return answer.id;
      });

      expect(await op.result, 'cancel');
    });

    test('повторный ответ игнорируется', () {
      final request = OperationRequest(
        message: 'Overwrite?',
        options: const [OperationRequestOption.overwrite, OperationRequestOption.skip],
        enterOption: OperationRequestOption.skip,
      );

      request.respond(OperationRequestOption.overwrite);
      request.respond(OperationRequestOption.skip);

      expect(request.isAnswered, isTrue);
      expect(request.answer, completion(OperationRequestOption.overwrite));
    });
  });

  group('CompletedOperation', () {
    test('готовое значение', () async {
      final op = CompletedOperation<int>(7);
      expect(await op.result, 7);
      expect(op.state, OperationState.complete);
    });

    test('готовая ошибка', () async {
      final op = CompletedOperation<int>.error(StateError('nope'));
      expect(op.state, OperationState.error);
      await expectLater(op.result, throwsA(isA<StateError>()));
    });
  });
  group('просьба прервать', () {
    /// Операция, считающая свои шаги: между ними стоит контрольная точка.
    ///
    /// Тело бесконечное — так видно и то, что работа встала, и то, что она
    /// пошла дальше.
    (TaskOperation<void>, List<int>) counting() {
      final steps = <int>[];
      final op = TaskOperation<void>((op) async {
        for (var i = 0; ; i++) {
          await op.checkpoint();
          steps.add(i);
          await Future<void>.delayed(Duration.zero);
        }
      });
      // Тело бесконечное: каждый такой тест кончается отменой, и её ошибку
      // читать некому.
      op.result.ignore();
      return (op, steps);
    }

    test('превращается в обычный вопрос, а не в отмену', () async {
      final (op, _) = counting();
      final questions = <OperationRequest>[];
      op.requests.listen(questions.add);

      op.requestCancel();
      await pumpEventQueue();

      expect(op.state, OperationState.processing);
      expect(questions.single.message, 'Abort the operation?');
      op.cancel();
    });

    test('до ответа работа стоит', () async {
      final (op, steps) = counting();
      OperationRequest? question;
      op.requests.listen((request) => question = request);

      op.requestCancel();
      await pumpEventQueue();
      final done = steps.length;

      await pumpEventQueue(times: 50);

      // Тело бесконечное: если бы оно работало, шагов стало бы больше.
      expect(steps.length, done);
      question!.respond(OperationRequestOption.resume);
      await pumpEventQueue();
      expect(steps.length, greaterThan(done));
      op.cancel();
    });

    test('повторная просьба задаёт вопрос заново', () async {
      final (op, _) = counting();
      final questions = <OperationRequest>[];
      op.requests.listen(questions.add);

      op.requestCancel();
      await pumpEventQueue();
      questions.single.respond(OperationRequestOption.resume);
      await pumpEventQueue();

      // Просьба не «залипает»: продолжив работу, её надо просить заново.
      expect(questions, hasLength(1));

      op.requestCancel();
      await pumpEventQueue();

      expect(questions, hasLength(2));
      op.cancel();
    });

    test('у законченной операции просить уже нечего', () async {
      final op = TaskOperation<int>((op) async => 1);
      await op.result;

      op.requestCancel();

      expect(op.state, OperationState.complete);
    });

    test('«Abort» завершает операцию отменой', () async {
      final (op, _) = counting();
      op.requests.listen((request) => request.respond(OperationRequestOption.abort));

      op.requestCancel();
      await pumpEventQueue();

      expect(op.state, OperationState.canceled);
    });
  });

  group('просьба прервать работу, которую не остановить', () {
    /// Операция, которая считает свои куски и не умеет ждать: между кусками
    /// стоит [TaskOperation.keepRunning], а не контрольная точка.
    ///
    /// Так ведёт себя копирование файла средствами системы: приостановить его
    /// нельзя, можно только бросить.
    (TaskOperation<void>, List<int>) chunking() {
      final chunks = <int>[];
      final op = TaskOperation<void>((op) async {
        for (var i = 0; ; i++) {
          if (!op.keepRunning()) {
            throw const OperationCanceled();
          }
          chunks.add(i);
          await Future<void>.delayed(Duration.zero);
        }
      });
      // Тело бесконечное: каждый такой тест кончается отменой, и её ошибку
      // читать некому.
      op.result.ignore();
      return (op, chunks);
    }

    test('пока не просили — работа идёт молча', () async {
      final (op, chunks) = chunking();
      final questions = <OperationRequest>[];
      op.requests.listen(questions.add);

      await pumpEventQueue(times: 10);

      expect(questions, isEmpty);
      expect(chunks, isNotEmpty);
      op.cancel();
    });

    test('вопрос задаётся один раз, а работа не встаёт', () async {
      final (op, chunks) = chunking();
      final questions = <OperationRequest>[];
      op.requests.listen(questions.add);

      op.requestCancel();
      await pumpEventQueue();
      final done = chunks.length;

      await pumpEventQueue(times: 50);

      // Ответа нет, а куски идут: вопрос поверх работы, а не вместо неё.
      expect(questions, hasLength(1));
      expect(chunks.length, greaterThan(done));
      expect(op.state, OperationState.processing);
      op.cancel();
    });

    test('«Resume» — работа как ни в чём не бывало', () async {
      final (op, chunks) = chunking();
      final questions = <OperationRequest>[];
      op.requests.listen(questions.add);

      op.requestCancel();
      await pumpEventQueue();
      questions.single.respond(OperationRequestOption.resume);
      await pumpEventQueue();
      final done = chunks.length;

      await pumpEventQueue(times: 10);

      expect(op.state, OperationState.processing);
      expect(chunks.length, greaterThan(done));

      // Просьба не «залипает»: продолжив работу, её надо просить заново.
      op.requestCancel();
      await pumpEventQueue();
      expect(questions, hasLength(2));
      op.cancel();
    });

    test('«Abort» доходит следующим куском', () async {
      final (op, _) = chunking();
      op.requests.listen((request) => request.respond(OperationRequestOption.abort));

      op.requestCancel();
      await pumpEventQueue();

      expect(op.state, OperationState.canceled);
    });

    test('спросить некого — работа бросается', () async {
      final (op, _) = chunking();

      op.requestCancel();
      await pumpEventQueue();

      // Без окна вопрос отвечает сам себя вариантом по умолчанию, и это
      // «прервать»: ровно то, о чём просили.
      expect(op.state, OperationState.canceled);
    });
  });

  group('делегирование вложенных', () {
    test('прогресс вложенной доходит до подписчика внешней', () async {
      final release = Completer<void>();
      // Вложенная рассказывает о себе раньше, чем внешняя успевает подписаться:
      // операция стартует сразу при создании, и первую веху спасает только
      // повтор последнего события новому подписчику.
      final inner = TaskOperation<int>((op) async {
        op.message('Reading a.zip');
        await release.future;
        return 1;
      });
      final outer = TaskOperation<int>((op) => op.delegate(inner));

      final seen = <String>[];
      outer.progress.listen((event) => seen.add(event.message));
      await pumpEventQueue();

      release.complete();
      expect(await outer.result, 1);
      expect(seen, ['Reading a.zip']);
    });

    test('веха объявляет долю неизвестной', () async {
      final op = TaskOperation<void>((op) async => op.message('Connecting'));
      final seen = <OperationProgress>[];
      op.progress.listen(seen.add);

      await op.result;
      await pumpEventQueue();

      expect(seen.single.message, 'Connecting');
      // Ноль процентов и «неизвестно сколько» — разные вещи, и полоса не должна
      // выдавать второе за первое.
      expect(seen.single.percent, isNull);
    });

    test('отмена внешней доходит до вложенной', () async {
      final inner = TaskOperation<int>((op) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 1;
      });
      final outer = TaskOperation<int>((op) => op.delegate(inner));
      await pumpEventQueue();

      outer.cancel();

      await expectLater(outer.result, throwsA(isA<OperationCanceled>()));
      expect(inner.state, OperationState.canceled);
    });

    test('отмена доходит через несколько уровней', () async {
      // Разбор пути рекурсивен, и работает всегда самая вложенная операция:
      // прерывать её приходится через всю цепочку.
      final inner = TaskOperation<int>((op) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return 1;
      });
      final middle = TaskOperation<int>((op) => op.delegate(inner));
      final outer = TaskOperation<int>((op) => op.delegate(middle));
      await pumpEventQueue();

      outer.cancel();

      await expectLater(outer.result, throwsA(isA<OperationCanceled>()));
      expect(middle.state, OperationState.canceled);
      expect(inner.state, OperationState.canceled);
    });

    test('делегирование из уже отменённой отменяет и вложенную', () async {
      // Отмена пришла, пока вложенную только создавали: работать она уже
      // начала, и бросить её без присмотра нельзя.
      late final TaskOperation<int> inner;
      final started = Completer<void>();
      final outer = TaskOperation<int>((op) async {
        started.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        inner = TaskOperation<int>((op) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return 1;
        })..result.ignore();
        return op.delegate(inner);
      });

      // Отменять до старта тела нельзя: такая операция вовсе не начнётся,
      // и делегировать станет нечего.
      await started.future;
      outer.cancel();
      await expectLater(outer.result, throwsA(isA<OperationCanceled>()));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(inner.state, OperationState.canceled);
    });

    test('завершённую вложенную отмена уже не трогает', () async {
      final inner = TaskOperation<int>((op) async => 1);
      final release = Completer<void>();
      final outer = TaskOperation<int>((op) async {
        final value = await op.delegate(inner);
        await release.future;
        return value;
      });
      await pumpEventQueue();
      expect(inner.state, OperationState.complete);

      outer.cancel();
      release.complete();

      await expectLater(outer.result, throwsA(isA<OperationCanceled>()));
      expect(inner.state, OperationState.complete);
    });

    test('ошибка вложенной приходит наружу как есть', () async {
      // Отказ открыть архив — это отказ, а не отмена: подменять одно другим
      // значило бы промолчать о причине.
      final inner = TaskOperation<int>((op) async => throw const FsError('/a.zip', FsErrorKind.io));
      final outer = TaskOperation<int>((op) => op.delegate(inner));

      await expectLater(outer.result, throwsA(isA<FsError>()));
      expect(outer.state, OperationState.error);
    });

    test('вопрос вложенной наверх не идёт: берётся вариант по умолчанию', () async {
      late final OperationRequestOption answer;
      final inner = TaskOperation<int>((op) async {
        answer = await op.ask(
          OperationRequest(
            message: 'Overwrite?',
            options: const [OperationRequestOption.overwrite, OperationRequestOption.skip],
            enterOption: OperationRequestOption.skip,
          ),
        );
        return 1;
      });
      final outer = TaskOperation<int>((op) => op.delegate(inner));

      final questions = <OperationRequest>[];
      outer.requests.listen(questions.add);

      expect(await outer.result, 1);
      expect(questions, isEmpty);
      expect(answer, OperationRequestOption.skip);
    });

    test('просьба прервать вниз не идёт', () async {
      // Мягкая отмена — это вопрос, а задать его вложенной некому: её вопросы
      // наверх не идут, и «спросить» молча превратилось бы в «прервать».
      final inner = TaskOperation<int>((op) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 1;
      });
      final outer = TaskOperation<int>((op) => op.delegate(inner));
      await pumpEventQueue();

      outer.requestCancel();
      await pumpEventQueue();

      expect(inner.state, OperationState.processing);
      expect(await outer.result, 1);
    });

    test('событие вложенной после конца внешней ничего не ломает', () async {
      final inner = _StubbornOperation();
      final outer = TaskOperation<int>((op) => op.delegate(inner));
      await pumpEventQueue();

      outer.cancel();
      await expectLater(outer.result, throwsA(isA<OperationCanceled>()));

      // Вложенная отмены не слушает и продолжает рассказывать о себе: её
      // события должны пропадать молча, а не падать в закрытый поток.
      inner.emit('Reading a.zip');
      await pumpEventQueue();

      expect(outer.state, OperationState.canceled);
      inner.finish();
    });
  });
}

/// Операция, которая отмены не слушает: так ведёт себя работа, которую нечем
/// прервать, — уже начатое подключение или запущенная внешняя программа.
class _StubbornOperation implements AsyncOperation<int> {
  final StreamController<OperationProgress> _progress = StreamController<OperationProgress>.broadcast();
  final Completer<int> _completer = Completer<int>();

  @override
  OperationState get state => _completer.isCompleted ? OperationState.complete : OperationState.processing;

  @override
  final OperationStatus status = _SilentStatus();

  @override
  Future<int> get result => _completer.future;

  @override
  Stream<OperationProgress> get progress => _progress.stream;

  @override
  Stream<OperationRequest> get requests => const Stream.empty();

  @override
  void cancel() {}

  @override
  void requestCancel() {}

  void emit(String message) => _progress.add(OperationProgress(message: message));

  void finish() {
    _completer.complete(1);
    _progress.close();
  }
}

/// Ход, о котором нечего рассказать: заглушке довольно быть Listenable.
class _SilentStatus extends ChangeNotifier implements OperationStatus {
  @override
  OperationState get state => OperationState.processing;

  @override
  String get message => '';
}
