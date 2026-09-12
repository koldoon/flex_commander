import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно «куда ходили»: список пройденного и прыжок к любому шагу
/// (`docs/spec/session-history.md`, §9).
void main() {
  late AppController app;
  late CommandService commands;

  Future<void> start(WidgetTester tester) async {
    final runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.directory('/home/pics'),
        FakeEntry.directory('/home/pics/2026'),
        FakeEntry.directory('/home/pics/2026/september-photos-from-the-long-trip-to-the-north'),
        FakeEntry.file('/home/notes.txt', size: 10),
      ])..home = '/home',
      modules: [const Navigation()],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    app = runtime.app;
    commands = runtime.commands;

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Пройти по трём каталогам — то, с чего начинается любая проверка истории.
  Future<void> walk(WidgetTester tester) async {
    await app.left.openPath('/home/docs');
    await app.left.openPath('/home/pics');
    await tester.pumpAndSettle();
  }

  Future<void> openWindow(WidgetTester tester) async {
    commands.run(ChooseHistoryCommand.commandId);
    await tester.pumpAndSettle();
  }

  /// Пути, показанные в окне, сверху вниз.
  List<String> shown(WidgetTester tester) => [
    for (final row in tester.widgetList<FcPickList>(find.byType(FcPickList)).first.rows) row.title,
  ];

  testWidgets('окно показывает всю историю, свежее сверху', (tester) async {
    await start(tester);
    await walk(tester);
    await openWindow(tester);

    expect(shown(tester), ['/home/pics', '/home/docs', '/home']);
  });

  testWidgets('текущий шаг помечен значком, и на нём стоит курсор', (tester) async {
    await start(tester);
    await walk(tester);
    await app.left.goBack();
    await tester.pumpAndSettle();
    await openWindow(tester);

    final list = tester.widgetList<FcPickList>(find.byType(FcPickList)).first;
    // Стоим на `/home/docs` — он второй сверху, потому что свежее него
    // остался `/home/pics`, куда ведёт «вперёд».
    expect(list.rows[1].marked, isTrue);
    expect(list.rows[0].marked, isFalse, reason: 'помечать «вперёд» нечем — там мы ещё не стоим');
    expect(list.selected, 1, reason: 'курсор открывается там, где сессия стоит сейчас');
  });

  testWidgets('набранное отбирает список', (tester) async {
    await start(tester);
    await walk(tester);
    await openWindow(tester);

    await tester.enterText(find.byType(TextField).first, 'doc');
    await tester.pumpAndSettle();

    expect(shown(tester), ['/home/docs']);
  });

  testWidgets('Enter ведёт на выбранный шаг и закрывает окно', (tester) async {
    await start(tester);
    await walk(tester);
    await openWindow(tester);

    // Вниз от текущего — это шаг назад: список идёт свежими вверх.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(app.left.currentPath, '/home');
    expect(find.byType(FcPickList), findsNothing, reason: 'окно осталось открытым');
  });

  testWidgets('прыжок «вперёд» не обрезает', (tester) async {
    await start(tester);
    await walk(tester);
    await openWindow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(app.left.currentPath, '/home/docs');
    expect(app.left.canGoForward, isTrue, reason: 'прыжок — ход по истории, а не новый переход');
  });

  testWidgets('длинный путь в списке обрезан с головы, а не с хвоста', (tester) async {
    const long = '/home/pics/2026/september-photos-from-the-long-trip-to-the-north';
    await start(tester);
    // Окно поуже, чтобы путь заведомо не поместился: в списке от него должен
    // остаться **конец** — тот каталог, о котором речь, как и в плашке пути.
    tester.view.physicalSize = const Size(620, 600);
    await app.left.openPath(long);
    await tester.pumpAndSettle();
    await openWindow(tester);

    final texts = [
      for (final row in tester.widgetList<Text>(
        find.descendant(of: find.byType(FcPickList), matching: find.byType(Text)),
      ))
        row.textSpan?.toPlainText() ?? row.data ?? '',
    ];
    final shown = texts.firstWhere((text) => text.endsWith('north'), orElse: () => '');

    expect(shown, isNotEmpty, reason: 'конец пути не виден вовсе: ${texts.join(' | ')}');
    expect(shown.length, lessThan(long.length), reason: 'путь не обрезан, хотя не помещается');
    expect(shown, startsWith('…'));
    expect(long, endsWith(shown.substring(1)));
  });

  testWidgets('пути стоят под текстом поля, а значок — в поле слева', (tester) async {
    await start(tester);
    await walk(tester);
    await openWindow(tester);

    final field = tester.getRect(find.byType(EditableText).first);
    final row = tester.getRect(find.descendant(of: find.byType(FcPickList), matching: find.byType(Text)).first);
    expect(row.left, moreOrLessEquals(field.left, epsilon: 1), reason: 'список съехал относительно набранного');

    final marker = tester.getRect(find.descendant(of: find.byType(FcPickList), matching: find.byType(Icon)).first);
    expect(marker.right, lessThanOrEqualTo(row.left + 1), reason: 'значок отнимает место у текста');
    expect(marker.left, greaterThanOrEqualTo(tester.getRect(find.byType(FcPickList)).left - 1));
  });

  testWidgets('Esc закрывает окно, ничего не тронув', (tester) async {
    await start(tester);
    await walk(tester);
    await openWindow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(FcPickList), findsNothing);
    expect(app.left.currentPath, '/home/pics');
  });

  testWidgets('одному шагу список не нужен', (tester) async {
    await start(tester);

    // Ходить ещё некуда: в истории только тот каталог, где панель стоит.
    expect(commands.run(ChooseHistoryCommand.commandId), isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(FcPickList), findsNothing);
  });
}
