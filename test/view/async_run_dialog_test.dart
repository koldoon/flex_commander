import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Каркас окна длительной работы: что он показывает и когда.
///
/// Форма здесь не «ветка иначе», а состояние: она видна ровно до начала работы.
/// Раньше окно откатывалось к ней на весь хвост работы — операция кончилась, а
/// команда ещё перечитывала панели.
void main() {
  const metrics = DefaultMetrics();

  late FcAsyncRun run;

  setUp(() async {
    final app = (await testApp(provider: InMemoryTreeProvider([FakeEntry.directory('/home')]))).app;
    run = FcAsyncRun(app: app, commandId: 'test.probe', title: 'Probe', failureMessage: 'Probe failed', show: () {});
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: FcAsyncRunDialog(
                run: run,
                form:
                    (context) => CommandDialogForm(
                      onCancel: run.dismiss,
                      onSubmit: run.submit,
                      submitLabel: 'Go',
                      error: run.error,
                      children: const [CommandDialogField.wide(child: Text('форма'))],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> work(Operation<Object?, void> operation) => run.run(operation, null, message: 'Working…');

  /// Работа, которая идёт, пока её не отпустят.
  ({Operation<Object?, void> operation, Completer<void> release}) hangingOperation() {
    final release = Completer<void>();
    return (operation: TaskOperation<void, void>((op, _) => release.future), release: release);
  }

  testWidgets('до начала работы видна форма', (tester) async {
    await pump(tester);

    expect(find.text('форма'), findsOneWidget);
    expect(find.byType(CommandDialogProgress), findsNothing);
  });

  testWidgets('пока работа идёт, видно ход дела, а кнопки живые', (tester) async {
    final hanging = hangingOperation();
    await pump(tester);

    final running = work(hanging.operation);
    await tester.pump();

    expect(find.text('форма'), findsNothing);
    expect(find.byType(CommandDialogProgress), findsOneWidget);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Cancel')).onPressed, isNotNull);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Background')).onPressed, isNotNull);

    hanging.release.complete();
    await running;
  });

  testWidgets('работа кончилась — окно замирает на ходе дела', (tester) async {
    await pump(tester);

    await work(TaskOperation<void, void>((op, _) async {}));
    await tester.pump();

    // Хвост работы: операции уже нет, окно ещё есть. Формы тут быть не должно
    // ни кадра — ровно за этим фаза прогона и заведена.
    expect(run.isBusy, isTrue);
    expect(find.text('форма'), findsNothing);
    expect(find.byType(CommandDialogProgress), findsOneWidget);
  });

  testWidgets('в хвосте работы обе кнопки погашены, но остаются на месте', (tester) async {
    await pump(tester);

    await work(TaskOperation<void, void>((op, _) async {}));
    await tester.pump();

    // Прерывать и прятать уже нечего, а переставлять ряд кнопок в момент
    // завершения — значит дёргать окно на прощание.
    expect(find.widgetWithText(FcButton, 'Background'), findsOneWidget);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Cancel')).onPressed, isNull);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Background')).onPressed, isNull);
  });

  testWidgets('ошибка после начала работы форму не воскрешает', (tester) async {
    await pump(tester);

    await work(TaskOperation<void, void>((op, _) async {}));
    run.error = '/backup: permission denied';
    await tester.pump();

    // Править ввод поздно: работа была начата. Остаётся сказать, что не вышло.
    expect(find.text('форма'), findsNothing);
    expect(find.text('Probe failed'), findsOneWidget);
    expect(find.text('/backup: permission denied'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'Close'), findsOneWidget);
  });

  testWidgets('ошибка до начала работы остаётся в форме', (tester) async {
    await pump(tester);

    run.error = 'Destination path is empty';
    await tester.pump();

    // Здесь наоборот: работа не начиналась, ввод можно поправить и повторить.
    expect(find.text('форма'), findsOneWidget);
    expect(find.text('Probe failed'), findsNothing);
  });

  testWidgets('вопрос по ходу работы вытесняет всё остальное', (tester) async {
    await pump(tester);

    final running = work(
      TaskOperation<void, void>((op, _) async {
        await op.ask(
          OperationRequest(
            message: 'File exists',
            options: const [TransferAnswers.skip, TransferAnswers.overwrite],
            enterOption: TransferAnswers.skip,
          ),
        );
      }),
    );
    await tester.pump();

    expect(find.text('File exists'), findsOneWidget);
    expect(find.byType(CommandDialogProgress), findsNothing);

    await tester.tap(find.widgetWithText(FcButton, 'Overwrite'));
    await running;
  });
}
