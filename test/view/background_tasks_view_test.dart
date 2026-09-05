import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/background_tasks_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Длительная работа, которой можно управлять из теста.
///
/// Устроена как настоящие: показывает окно и уходит. Прогон она держит только
/// ради теста — ему нужно за что-то ухватиться.
class _SlowCommand extends AppCommand {
  _SlowCommand(this.operation);

  final TaskOperation<void, void> operation;

  FcAsyncRun? lastRun;

  /// Заголовок полоски задаёт заводивший работу, а не имя команды. Тест меняет
  /// его между запусками, чтобы различать строки списка.
  String dialogTitle = 'Copy 3 items';

  @override
  String get id => 'test.slow';

  @override
  String get label => 'Slow work';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {
    final view = context.app.view;
    final title = dialogTitle;
    late final FcAsyncRun run;

    void present() {
      late final String dialogId;
      run.close = () => view.closeDialog(dialogId);
      dialogId = view.showDialog(
        DialogSpec(title: title, content: const SizedBox.shrink(), onSubmit: run.submit, onDismiss: run.dismiss),
      );
    }

    run = FcAsyncRun(app: context.app, commandId: id, title: title, failureMessage: 'Slow work failed', show: present);
    run.onStart = () => run.run(operation, null, message: 'Working…');
    lastRun = run;

    present();
  }
}

class _SlowModule implements FcFrontendModule {
  _SlowModule(this.command);

  final _SlowCommand command;

  @override
  String get id => 'test.slow';

  @override
  String get title => 'Slow work';

  @override
  void installFrontend(FrontendRegistry registry) => registry.command((context) => command);
}

/// Список работ, ушедших в фон: место, вид и клавиши.
///
/// Спецификация — `docs/spec/background-operations.md`.
void main() {
  late bool done;
  late _SlowCommand command;
  late AppRuntime runtime;

  /// Работа, которая идёт, пока тест не скажет «хватит».
  TaskOperation<void, void> slowWork() => TaskOperation<void, void>((op, _) async {
    while (!done) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await op.checkpoint();
    }
  });

  setUp(() => done = false);

  tearDown(() => done = true);

  Future<void> pumpApp(WidgetTester tester, {List<FakeEntry> entries = const [], int iconSize = 0}) async {
    // Работа заводится **внутри** теста: созданная в `setUp`, она осталась бы
    // вне поддельного времени прогона, и её проверки не двигались бы вовсе.
    command = _SlowCommand(slowWork());
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings();
    settings.modules.scope('fc.icons').section(FileIconSettings.new).size = iconSize;

    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), ...entries])..home = '/home',
      modules: [...featureModules(), _SlowModule(command)],
      settings: settings,
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  /// Заводит работу и отправляет её в фон.
  Future<FcAsyncRun> sendToBackground(WidgetTester tester, {String title = 'Copy 3 items'}) async {
    command.dialogTitle = title;
    expect(runtime.commands.run('test.slow'), isTrue);
    final run = command.lastRun!;
    unawaited(run.submit());
    await tester.pump(const Duration(milliseconds: 5));
    run.sendToBackground();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    return run;
  }

  Future<void> press(WidgetTester tester, String keys) async {
    runtime.commands.dispatch(KeyCombination.parse(keys));
    await tester.pumpAndSettle();
  }

  /// Прогон закончен: работа останавливается, а таймеры дорабатывают.
  Future<void> settle(WidgetTester tester) async {
    done = true;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  testWidgets('список стоит под своей панелью, а под чужой его нет', (tester) async {
    await pumpApp(tester);

    // Пока работы нет, области нет вовсе: место она занимает, только когда есть
    // что показать.
    expect(find.byType(BackgroundTasksView), findsNothing);

    await sendToBackground(tester);

    expect(runtime.app.operations.at(ViewportPosition.left), hasLength(1));
    expect(runtime.app.operations.at(ViewportPosition.right), isEmpty);
    expect(find.byType(BackgroundTasksView), findsOneWidget);
    // Заголовок — тот, что задал заводивший работу, а не имя команды.
    expect(find.text('Copy 3 items: '), findsOneWidget);

    await settle(tester);
  });

  testWidgets('панель, полоса поиска и список работ отбиты одним зазором', (tester) async {
    // Области под панелью своих отступов не отмеряют: зазоры между ними ставит
    // шелл, одной величиной (`spec/layout-gaps.md`).
    await pumpApp(tester, entries: [FakeEntry.file('/home/notes.txt', size: 10)]);
    await sendToBackground(tester);

    // Под той же панелью — ещё и полоса поиска: областей под ней сразу две, и
    // проверяется как раз ряд из них.
    await press(tester, 'Ctrl-S');

    final gap = FcTheme.of(tester.element(find.byType(QuickSearchView))).metrics.areaGap;
    final panel = tester.getRect(find.byType(PanelView).first);
    final search = tester.getRect(find.byType(QuickSearchView));
    final work = tester.getRect(find.byType(BackgroundTasksView));

    expect(search.top - panel.bottom, closeTo(gap, 0.01), reason: 'панель — поиск');
    expect(work.top - search.bottom, closeTo(gap, 0.01), reason: 'поиск — работа');

    await settle(tester);
  });

  testWidgets('щелчок по строке возвращает окно работы', (tester) async {
    // Целятся именно в строку, а не в мелкий знак вопроса рядом: она и есть то,
    // что видно на экране от ушедшей в фон работы.
    await pumpApp(tester);
    await sendToBackground(tester);

    expect(runtime.app.view.dialogs, isEmpty, reason: 'окно ушло в фон');

    await tester.tap(find.text('Copy 3 items: '));
    await tester.pump();

    expect(runtime.app.view.dialogs, hasLength(1), reason: 'и вернулось по щелчку');
    expect(runtime.app.operations.at(ViewportPosition.left), isEmpty, reason: 'из фона — значит из списка');

    await settle(tester);
  });

  testWidgets('крестик возвращает окно сразу, а не через «нужен ответ»', (tester) async {
    await pumpApp(tester);
    final run = await sendToBackground(tester);

    expect(runtime.app.view.dialogs, isEmpty);

    // Нажатый крестик и есть внимание человека: он смотрит сюда и уже решил.
    await tester.tap(find.text('✕'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Окно вернулось само, и вопрос уже в нём — второй кнопки на пути нет.
    expect(runtime.app.view.dialogs, hasLength(1));
    expect(run.question, isNotNull);
    expect(runtime.app.operations.at(ViewportPosition.left), isEmpty);

    done = true;
    await run.submit();
    await tester.pumpAndSettle();
  });

  testWidgets('Cmd-B уводит ввод в список, Esc возвращает его панели', (tester) async {
    await pumpApp(tester);
    await sendToBackground(tester);

    expect(runtime.app.view.activeArea, ViewportPosition.left, reason: 'ввод у панели');

    await press(tester, 'Cmd-B');
    expect(runtime.app.view.activeArea, ViewportPosition.leftStatus, reason: 'и ушёл в список');

    await press(tester, 'Esc');
    expect(runtime.app.view.activeArea, ViewportPosition.left, reason: 'и вернулся');

    await settle(tester);
  });

  testWidgets('стрелки водят курсор, Enter возвращает окно выбранной работы', (tester) async {
    await pumpApp(tester);
    await sendToBackground(tester, title: 'Copy 3 items');
    final second = await sendToBackground(tester, title: 'Find in files');

    await press(tester, 'Cmd-B');
    await press(tester, 'Down');
    await press(tester, 'Enter');

    expect(runtime.app.view.dialogs, hasLength(1));
    expect(runtime.app.view.dialogs.single.title, 'Find in files', reason: 'вернулась та, что под курсором');
    expect(second.question, isNull, reason: 'её просто показали, а не прервали');

    await settle(tester);
  });

  testWidgets('Bsp отменяет работу под курсором — как крестик', (tester) async {
    await pumpApp(tester);
    final run = await sendToBackground(tester);

    await press(tester, 'Cmd-B');
    await press(tester, 'Bsp');
    await tester.pump(const Duration(milliseconds: 20));

    expect(runtime.app.view.dialogs, hasLength(1), reason: 'окно вернулось до вопроса');
    expect(run.question, isNotNull, reason: 'работу попросили прерваться');

    done = true;
    await run.submit();
    await tester.pumpAndSettle();
  });

  testWidgets('работ нет — вести ввод некуда', (tester) async {
    await pumpApp(tester);

    final command = runtime.commands.create('app.background')!;
    expect(runtime.commands.isExecutable(command), isFalse);
    await press(tester, 'Cmd-B');
    expect(runtime.app.view.activeArea, ViewportPosition.left);
  });

  testWidgets('работ больше четырёх — видно четыре, дальше прокрутка', (tester) async {
    await pumpApp(tester);
    for (var i = 0; i < 6; i++) {
      await sendToBackground(tester, title: 'Work $i');
    }

    expect(runtime.app.operations.at(ViewportPosition.left), hasLength(6));

    // Шаг строки берётся там же, где его берёт список файлов, — одной величиной
    // на оба списка.
    final theme = FcTheme.of(tester.element(find.byType(BackgroundTasksView)));
    final line = FileIconSize.listRow(theme.metrics, runtime.app.fileIcons);
    final list = find.descendant(of: find.byType(BackgroundTasksView), matching: find.byType(ListView));

    expect(tester.getRect(list).height, closeTo(line * BackgroundTasksView.visibleRows, 0.01));

    await settle(tester);
  });

  testWidgets('список работ совпадает с эталоном', (tester) async {
    // Снимок: рама, курсор и три строки под панелью. Обновление —
    // `flutter test --update-goldens`.
    await pumpApp(tester, entries: [FakeEntry.file('/home/notes.txt', size: 10)]);
    await sendToBackground(tester, title: 'Copy 3 items');
    await sendToBackground(tester, title: 'Find in files');
    await sendToBackground(tester, title: 'Pack archive.zip');

    // Ввод в списке: курсор виден только там, где клавиши, и снимок обязан
    // показать именно это.
    await press(tester, 'Cmd-B');
    await press(tester, 'Down');

    await expectLater(find.byType(FlexCommanderApp), matchesGoldenFile('goldens/background_tasks.png'));

    await settle(tester);
  });

  testWidgets('ввод ушёл в список — курсор панели погас', (tester) async {
    // Курсор горит там, куда попадёт следующее нажатие. Пока он горел у панели
    // и в списке разом, было непонятно, кому достанутся стрелки.
    await pumpApp(tester, entries: [FakeEntry.file('/home/notes.txt', size: 10)]);
    await sendToBackground(tester);

    expect(tester.widget<FileTableRow>(find.byType(FileTableRow).first).panelActive, isTrue);

    await press(tester, 'Cmd-B');
    expect(
      tester.widget<FileTableRow>(find.byType(FileTableRow).first).panelActive,
      isFalse,
      reason: 'клавиши у списка работ, а курсор панели всё ещё горит',
    );

    await press(tester, 'Esc');
    expect(tester.widget<FileTableRow>(find.byType(FileTableRow).first).panelActive, isTrue);

    await settle(tester);
  });

  testWidgets('у единственной строки просвет сверху и снизу одинаков', (tester) async {
    // Первая строка стоит сразу под рамой: подсветка прилегала к ней вплотную,
    // а просвет оставался только снизу.
    await pumpApp(tester);
    await sendToBackground(tester);
    await press(tester, 'Cmd-B');

    final list = tester.getRect(find.descendant(of: find.byType(BackgroundTasksView), matching: find.byType(ListView)));
    final cursor = tester.getRect(
      find.descendant(of: find.byType(BackgroundTasksView), matching: find.byType(DecoratedBox)).last,
    );

    expect(cursor.top - list.top, closeTo(list.bottom - cursor.bottom, 0.01));
    expect(cursor.top - list.top, greaterThan(0));

    await settle(tester);
  });

  testWidgets('шаг строк совпадает со списком файлов и при крупной иконке', (tester) async {
    // Величина одна на оба списка: они видны разом, в двух точках друг от
    // друга. Со своей формулой ритм совпадал бы только при размере иконки по
    // умолчанию — а его как раз и меняют.
    await pumpApp(tester, entries: [FakeEntry.file('/home/notes.txt', size: 10)], iconSize: 24);
    await sendToBackground(tester);

    final lists = find.byType(ListView);
    final panel = tester.widget<ListView>(lists.first);
    final tasks = tester.widget<ListView>(find.descendant(of: find.byType(BackgroundTasksView), matching: lists));
    final metrics = FcTheme.of(tester.element(find.byType(BackgroundTasksView))).metrics;

    expect(panel.itemExtent, greaterThan(metrics.rowHeight), reason: 'крупная иконка подняла строку панели');
    expect(tasks.itemExtent, panel.itemExtent, reason: 'а список работ пошёл за ней');

    await settle(tester);
  });

  testWidgets('забыли последнюю работу — ввод вернулся панели сам', (tester) async {
    await pumpApp(tester);
    final run = await sendToBackground(tester);

    await press(tester, 'Cmd-B');
    expect(runtime.app.view.activeArea, ViewportPosition.leftStatus);

    runtime.app.operations.forget(run.runId);
    await tester.pumpAndSettle();

    expect(find.byType(BackgroundTasksView), findsNothing, reason: 'области больше нет');
    expect(runtime.app.view.activeArea, ViewportPosition.left, reason: 'и ввод вернулся панели');

    await settle(tester);
  });
}
