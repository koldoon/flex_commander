import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/session_commands.dart';
import 'package:flex_commander/view/sessions_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно выбора набора (`docs/spec/panel-sessions.md`, §3).
void main() {
  late AppController app;

  setUp(() async {
    app =
        (await testApp(
          provider: InMemoryTreeProvider([
            FakeEntry.directory('/home'),
            FakeEntry.directory('/home/docs'),
            FakeEntry.directory('/work'),
            FakeEntry.directory('/work/reports'),
            FakeEntry.directory('/work/qwickserve-flex-applications'),
            FakeEntry.directory('/work/qwickserve-flex-applications/generated-sources'),
            FakeEntry.directory('/work/qwickserve-flex-applications/generated-sources/dist'),
          ]),
          modules: featureModules(),
          settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/docs')),
        )).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Ещё один набор — на названном каталоге и со своим именем.
  Future<Panel> addSession(WidgetTester tester, {required String path, required String name}) async {
    final panel = await app.openPanel(ViewportPosition.left);
    await panel.session.openPath(path);
    app.renamePanel(panel, name);
    await tester.pumpAndSettle();
    return panel;
  }

  Future<void> openDialog(WidgetTester tester) async {
    app.commands.run(SelectSessionCommand.commandId);
    await tester.pumpAndSettle();
  }

  /// Строки списка — прямо с виджета: текст в них нарезан на отрезки.
  List<FcPickRow> shown(WidgetTester tester) => tester.widgetList<FcPickList>(find.byType(FcPickList)).first.rows;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(of: find.byType(SessionsDialogForm), matching: find.byType(EditableText)),
      text,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('окно показывает все наборы — и непоказанные тоже', (tester) async {
    await pumpApp(tester);
    await addSession(tester, path: '/work', name: 'сборка');
    // Заведённый показан слева; вернём туда первый, чтобы «сборка» осталась ни
    // в одной панели.
    app.showPanel(ViewportPosition.left, app.panels.first);
    await tester.pumpAndSettle();

    await openDialog(tester);

    expect(shown(tester).map((row) => row.title), contains('сборка'));
    expect(shown(tester), hasLength(app.panels.length));
  });

  testWidgets('порядок — по заведению, а не по алфавиту', (tester) async {
    await pumpApp(tester);
    await addSession(tester, path: '/work', name: 'яблоко');
    await addSession(tester, path: '/work/reports', name: 'абрикос');

    await openDialog(tester);

    // Номера `Alt-N` — это места в списке, и окно обязано идти теми же
    // номерами: не по алфавиту, где «абрикос» встал бы впереди «яблока», и не
    // по времени заведения — заведённый встаёт рядом с показанным (§3).
    final titles = shown(tester).map((row) => row.title).toList();
    expect(titles, [for (final panel in app.panels) panelTitle(panel, app.panels)]);
    expect(titles.indexOf('яблоко'), lessThan(titles.indexOf('абрикос')));
  });

  testWidgets('номер стоит у первых девяти', (tester) async {
    await pumpApp(tester);

    await openDialog(tester);

    final rows = shown(tester);
    expect(rows[0].leading, '1');
    expect(rows[1].leading, '2');
    expect(rows.every((row) => row.title.startsWith(row.leading) == false), isTrue, reason: 'номер — не часть имени');
  });

  testWidgets('курсор встаёт на набор, показанный здесь', (tester) async {
    await pumpApp(tester);
    await addSession(tester, path: '/work', name: 'сборка');

    await openDialog(tester);

    final selected = tester.widgetList<FcPickList>(find.byType(FcPickList)).first.selected;
    expect(shown(tester)[selected].title, 'сборка', reason: 'уходят чаще всего отсюда — видно, откуда');
  });

  testWidgets('отбор находит и по имени, и по пути', (tester) async {
    await pumpApp(tester);
    await addSession(tester, path: '/work/reports', name: 'сборка');

    await openDialog(tester);
    await type(tester, 'сбор');
    expect(shown(tester).map((row) => row.title), ['сборка']);

    // Путь показан приглушённо за именем — и ищется наравне.
    await type(tester, 'reports');
    expect(shown(tester).map((row) => row.title), ['сборка']);
  });

  testWidgets('Enter показывает выбранное в активной панели и закрывает окно', (tester) async {
    await pumpApp(tester);
    await addSession(tester, path: '/work', name: 'сборка');
    app.showPanel(ViewportPosition.left, app.panels.first);
    await tester.pumpAndSettle();

    await openDialog(tester);
    await type(tester, 'сбор');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(app.panelAt(ViewportPosition.left).name, 'сборка');
    expect(find.byType(SessionsDialogForm), findsNothing, reason: 'окно осталось открытым');
  });

  testWidgets('щелчок по строке показывает набор здесь же', (tester) async {
    await pumpApp(tester);
    await addSession(tester, path: '/work', name: 'сборка');
    app.showPanel(ViewportPosition.left, app.panels.first);
    await tester.pumpAndSettle();

    await openDialog(tester);
    await tester.tap(find.textContaining('сборка', findRichText: true).last);
    await tester.pumpAndSettle();

    expect(app.panelAt(ViewportPosition.left).name, 'сборка');
    expect(find.byType(SessionsDialogForm), findsNothing);
  });

  testWidgets('мини-пара горит у показанных: левая — слева, правая — справа', (tester) async {
    await pumpApp(tester);

    await openDialog(tester);

    // Два набора при запуске: первый показан слева, второй справа.
    expect(find.byKey(SessionsDialogForm.leftMarkKey), findsOneWidget);
    expect(find.byKey(SessionsDialogForm.rightMarkKey), findsOneWidget);
  });

  testWidgets('отбор ничего не нашёл — Enter ничего не делает, окно стоит', (tester) async {
    await pumpApp(tester);
    final was = app.panelAt(ViewportPosition.left);

    await openDialog(tester);
    await type(tester, 'такого-набора-нет');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(SessionsDialogForm), findsOneWidget, reason: 'закрывать в пустоту — терять набранное');
    expect(identical(app.panelAt(ViewportPosition.left), was), isTrue);
  });

  testWidgets('длинный путь режется слева, и корень виден', (tester) async {
    // Хвостовое многоточие теряло и корень, и тот каталог, о котором речь
    // (поймано живьём).
    await pumpApp(tester);
    await addSession(tester, path: '/work/qwickserve-flex-applications/generated-sources/dist', name: 'сборка');

    await openDialog(tester);
    await type(tester, 'сбор');

    // Не первый попавшийся: слева от имени своим отрезком стоит номер.
    final row = tester
        .widgetList<RichText>(find.descendant(of: find.byType(FcPickList), matching: find.byType(RichText)))
        .map((text) => text.text.toPlainText())
        .firstWhere((text) => text.startsWith('сборка'));

    expect(row, contains('/…'), reason: 'корень остаётся: по нему видно, о каком диске речь');
    expect(row, endsWith('dist'), reason: 'в конце тот каталог, о котором речь');
  });

  testWidgets('Esc закрывает окно, ничего не меняя', (tester) async {
    await pumpApp(tester);
    final was = app.panelAt(ViewportPosition.left);

    await openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(SessionsDialogForm), findsNothing);
    expect(identical(app.panelAt(ViewportPosition.left), was), isTrue);
  });
}
