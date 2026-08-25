import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Команда с длительной работой, которой можно управлять из теста.
class _ProbeCommand extends AsyncCommandBase {
  @override
  String get id => 'test.probe';

  @override
  String get label => 'Probe';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() async {}

  Future<void> run(AsyncOperation<void> operation) => runOperation(operation, message: 'Working…');

  /// Ошибка, с которой прогон закончился: её ставит [AppCommand.submit], а в
  /// тесте — сам тест.
  void fail(String message) => error = message;
}

/// Каркас окна длительной работы: что он показывает и когда.
///
/// Форма здесь не «ветка иначе», а состояние: она видна ровно до начала работы.
/// Раньше окно откатывалось к ней на весь хвост работы — операция кончилась, а
/// команда ещё перечитывает панели.
void main() {
  const metrics = DefaultMetrics();

  late _ProbeCommand command;

  setUp(() => command = _ProbeCommand());

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
              child: AsyncCommandDialog(
                command: command,
                form:
                    (context) => CommandDialogForm(
                      onCancel: command.dismiss,
                      onSubmit: command.submit,
                      submitLabel: 'Go',
                      error: command.error,
                      children: const [Text('форма')],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Работа, которая идёт, пока её не отпустят.
  ({AsyncOperation<void> operation, Completer<void> release}) hangingOperation() {
    final release = Completer<void>();
    return (operation: TaskOperation<void>((op) => release.future), release: release);
  }

  testWidgets('до начала работы видна форма', (tester) async {
    await pump(tester);

    expect(find.text('форма'), findsOneWidget);
    expect(find.byType(CommandDialogProgress), findsNothing);
  });

  testWidgets('пока работа идёт, видно ход дела, а кнопки живые', (tester) async {
    final hanging = hangingOperation();
    await pump(tester);

    final run = command.run(hanging.operation);
    await tester.pump();

    expect(find.text('форма'), findsNothing);
    expect(find.byType(CommandDialogProgress), findsOneWidget);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Cancel')).onPressed, isNotNull);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Background')).onPressed, isNotNull);

    hanging.release.complete();
    await run;
  });

  testWidgets('работа кончилась — окно замирает на ходе дела', (tester) async {
    await pump(tester);

    await command.run(TaskOperation<void>((op) async {}));
    await tester.pump();

    // Хвост работы: операции уже нет, окно ещё есть. Формы тут быть не должно
    // ни кадра — ровно за этим фаза прогона и заведена.
    expect(command.phase, CommandRunPhase.done);
    expect(find.text('форма'), findsNothing);
    expect(find.byType(CommandDialogProgress), findsOneWidget);
  });

  testWidgets('в хвосте работы обе кнопки погашены, но остаются на месте', (tester) async {
    await pump(tester);

    await command.run(TaskOperation<void>((op) async {}));
    await tester.pump();

    // Прерывать и прятать уже нечего, а переставлять ряд кнопок в момент
    // завершения — значит дёргать окно на прощание.
    expect(find.widgetWithText(FcButton, 'Background'), findsOneWidget);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Cancel')).onPressed, isNull);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Background')).onPressed, isNull);
  });

  testWidgets('ошибка после начала работы форму не воскрешает', (tester) async {
    await pump(tester);

    await command.run(TaskOperation<void>((op) async {}));
    command.fail('/backup: permission denied');
    await tester.pump();

    // Править ввод поздно: работа была начата. Остаётся сказать, что не вышло.
    expect(find.text('форма'), findsNothing);
    expect(find.text('Probe failed'), findsOneWidget);
    expect(find.text('/backup: permission denied'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'Close'), findsOneWidget);
  });

  testWidgets('ошибка до начала работы остаётся в форме', (tester) async {
    await pump(tester);

    command.fail('Destination path is empty');
    await tester.pump();

    // Здесь наоборот: работа не начиналась, ввод можно поправить и повторить.
    expect(find.text('форма'), findsOneWidget);
    expect(find.text('Probe failed'), findsNothing);
  });

  testWidgets('вопрос по ходу работы вытесняет всё остальное', (tester) async {
    await pump(tester);
    // Без окна ядро отвечает за пользователя вариантом по умолчанию: команду
    // мог запустить сценарий, и спросить там некого.
    command.setDialogOpen(true);

    final run = command.run(
      TaskOperation<void>((op) async {
        await op.ask(
          ChoiceRequest(
            message: 'File exists',
            options: const [OperationOption.skip, OperationOption.overwrite],
            enterOption: OperationOption.skip,
          ),
        );
      }),
    );
    await tester.pump();

    expect(find.text('File exists'), findsOneWidget);
    expect(find.byType(CommandDialogProgress), findsNothing);

    await tester.tap(find.widgetWithText(FcButton, 'Overwrite'));
    await run;
  });
}
