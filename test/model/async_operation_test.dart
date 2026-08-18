import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskOperation', () {
    test('возвращает результат и завершается', () async {
      final op = TaskOperation<int>((op) async => 42);

      expect(await op.result, 42);
      expect(op.status, OperationStatus.complete);
      expect(op.status.isFinished, isTrue);
    });

    test('ошибка тела попадает в результат', () async {
      final op = TaskOperation<int>((op) async => throw StateError('boom'));

      await expectLater(op.result, throwsA(isA<StateError>()));
      expect(op.status, OperationStatus.error);
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
      expect(op.status, OperationStatus.canceled);
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
      expect(op.status, OperationStatus.canceled);
    });

    test('повторная отмена ничего не ломает', () async {
      final op = TaskOperation<int>((op) async => 1);
      await op.result;

      op.cancel();
      expect(op.status, OperationStatus.complete);
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
            options: const [OperationOption.overwrite, OperationOption.skip],
          ),
        );
        return answer.id;
      });
      op.requests.listen((request) => request.respond(OperationOption.skip));

      expect(await op.result, 'skip');
    });

    test('без подписчиков применяется вариант по умолчанию', () async {
      final op = TaskOperation<String>((operation) async {
        final answer = await operation.ask(
          OperationRequest(
            message: 'Overwrite file?',
            options: const [OperationOption.overwrite, OperationOption.cancel],
          ),
        );
        return answer.id;
      });

      expect(await op.result, 'cancel');
    });

    test('повторный ответ игнорируется', () {
      final request = OperationRequest(
        message: 'Overwrite?',
        options: const [OperationOption.overwrite, OperationOption.skip],
      );

      request.respond(OperationOption.overwrite);
      request.respond(OperationOption.skip);

      expect(request.isAnswered, isTrue);
      expect(request.answer, completion(OperationOption.overwrite));
    });
  });

  group('CompletedOperation', () {
    test('готовое значение', () async {
      final op = CompletedOperation<int>(7);
      expect(await op.result, 7);
      expect(op.status, OperationStatus.complete);
    });

    test('готовая ошибка', () async {
      final op = CompletedOperation<int>.error(StateError('nope'));
      expect(op.status, OperationStatus.error);
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

      expect(op.status, OperationStatus.processing);
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
      question!.respond(OperationOption.resume);
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
      questions.single.respond(OperationOption.resume);
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

      expect(op.status, OperationStatus.complete);
    });

    test('«Abort» завершает операцию отменой', () async {
      final (op, _) = counting();
      op.requests.listen((request) => request.respond(OperationOption.abort));

      op.requestCancel();
      await pumpEventQueue();

      expect(op.status, OperationStatus.canceled);
    });
  });
}
