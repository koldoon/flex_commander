import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/view/status_area.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Длительная работа, которой можно управлять из теста.
class _SlowCommand extends AsyncCommandBase {
  _SlowCommand(this.operation);

  final TaskOperation<void> operation;

  @override
  String get id => 'test.slow';

  @override
  String get label => 'Slow work';

  @override
  String get dialogTitle => 'Copy 3 items';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute() => runOperation(operation, message: 'Working…');
}

class _SlowModule implements FcModule {
  _SlowModule(this.operation);

  final TaskOperation<void> operation;

  @override
  String get id => 'test.slow';

  @override
  String get title => 'Slow work';

  @override
  void install(FcRegistry registry) => registry.command((context) => _SlowCommand(operation));
}

/// Работа показывается под той панелью, с которой её запустили.
///
/// Не в общей полосе на всё окно: копирование идёт из панели, и место ему под
/// ней. Иначе по двум работам не понять, какая откуда.
void main() {
  testWidgets('полоска стоит под своей панелью, а под чужой её нет', (tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var done = false;
    final operation = TaskOperation<void>((op) async {
      while (!done) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await op.checkpoint();
      }
    });
    addTearDown(() => done = true);

    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: [...featureModules(), _SlowModule(operation)],
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    // Пока работы нет, области нет вовсе: место она занимает, только когда
    // есть что показать.
    for (final area in tester.widgetList<StatusArea>(find.byType(StatusArea))) {
      expect(runtime.app.operations.at(area.owner), isEmpty);
    }
    expect(find.text('Copy 3 items'), findsNothing);

    expect(runtime.commands.run('test.slow'), isTrue);
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await tester.pump(const Duration(milliseconds: 5));

    runtime.app.operations.sendToBackground(run.runId, owner: ViewportPosition.left);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(runtime.app.operations.at(ViewportPosition.left), hasLength(1));
    expect(runtime.app.operations.at(ViewportPosition.right), isEmpty);
    // Заголовок — тот, что задал заводивший работу, а не имя команды.
    expect(find.text('Copy 3 items: '), findsOneWidget);

    done = true;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  });

  testWidgets('крестик возвращает окно сразу, а не через «нужен ответ»', (tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var done = false;
    final operation = TaskOperation<void>((op) async {
      while (!done) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await op.checkpoint();
      }
    });
    addTearDown(() => done = true);

    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: [...featureModules(), _SlowModule(operation)],
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    expect(runtime.commands.run('test.slow'), isTrue);
    final run = runtime.commands.openDialogs.single as AsyncCommandBase;
    unawaited(run.submit());
    await tester.pump(const Duration(milliseconds: 5));
    runtime.app.operations.sendToBackground(run.runId, owner: ViewportPosition.left);
    await tester.pump();

    expect(runtime.commands.openDialogs, isEmpty);

    // Нажатый крестик и есть внимание человека: он смотрит сюда и уже решил.
    await tester.tap(find.text('✕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Окно вернулось само, и вопрос уже в нём — второй кнопки на пути нет.
    expect(runtime.commands.openDialogs.single, same(run));
    expect(run.question, isNotNull);
    expect(runtime.app.operations.at(ViewportPosition.left), isEmpty);

    done = true;
    await run.submit();
    await tester.pumpAndSettle();
  });
}
