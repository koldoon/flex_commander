import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вид «Столбцы»: путь цепочкой каталогов.
///
/// Спецификация — `docs/spec/panel-view-columns.md`.
void main() {
  List<FakeEntry> entries() => [
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/lib'),
    FakeEntry.directory('/home/lib/src'),
    FakeEntry.directory('/home/test'),
    FakeEntry.file('/home/main.dart', size: 10),
    FakeEntry.file('/home/lib/app.dart', size: 20),
    FakeEntry.file('/home/lib/src/panel.dart', size: 30),
    FakeEntry.file('/home/test/panel_test.dart', size: 40),
  ];

  InMemoryTreeProvider provider() => InMemoryTreeProvider(entries())..home = '/home';

  Future<AppRuntime> open(WidgetTester tester, {String at = '/home', Size size = const Size(1200, 600)}) async {
    final settings = AppSettings(left: PanelSettings.defaults(at), right: PanelSettings.defaults('/home'));
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settings);
    await runtime.app.start();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(ColumnsView.viewId);
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Списки столбцов, слева направо.
  Finder columns() => find.descendant(of: find.byType(ColumnsView), matching: find.byType(ListView));

  /// Что видно в столбце: имена сверху вниз, без глифов значков.
  List<String> namesIn(WidgetTester tester, int column) => [
    for (final text in tester.widgetList<Text>(find.descendant(of: columns().at(column), matching: find.byType(Text))))
      if ((text.data ?? '').isNotEmpty && (text.data ?? '').codeUnitAt(0) < 0xE000) text.data!,
  ];

  testWidgets('Cmd-6 разворачивает цепочку до каталога панели', (tester) async {
    await open(tester, at: '/home/lib');

    // Три столбца: содержимое корня, `/home` и `/home/lib` — весь путь разом.
    expect(tester.widgetList(columns()).length, 3);
    expect(namesIn(tester, 0), contains('home'));
    expect(namesIn(tester, 1), containsAll(['lib', 'test', 'main.dart']));
    expect(namesIn(tester, 2), containsAll(['src', 'app.dart']));
  });

  testWidgets('столбец подписан именем своего каталога', (tester) async {
    await open(tester, at: '/home/lib');

    // Шапка называет тот каталог, чьё содержимое в столбце, — последнее звено
    // пути, из которого столбец вырос.
    final headers =
        tester
            .widgetList<Text>(find.descendant(of: find.byType(ColumnsView), matching: find.byType(Text)))
            .map((text) => text.data)
            .toList();
    expect(headers, containsAllInOrder(['/', 'home', 'lib']));

    // И это именно шапки, а не строки: в списках этих имён нет.
    expect(namesIn(tester, 2), isNot(contains('lib')));
  });

  testWidgets('курсор остаётся на том же объекте, что и в списке', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;

    panel.setCursorToName('main.dart');
    await tester.pumpAndSettle();
    await panel.setView(ColumnsView.viewId);
    await tester.pumpAndSettle();

    expect(panel.currentEntry?.name, 'main.dart', reason: 'смена вида курсор не двигает');
  });

  testWidgets('щелчок ставит курсор, двойной — уводит внутрь', (tester) async {
    final runtime = await open(tester, at: '/home');
    final panel = runtime.app.left;

    Finder row(String name) => find.descendant(of: find.byType(ColumnsView), matching: find.text(name));

    await tester.tap(row('test'));
    await tester.pumpAndSettle();
    expect(panel.currentEntry?.name, 'test');

    // Второй щелчок по той же строке — каталог раскрывается, и справа
    // появляется его содержимое.
    await tester.tap(row('test'));
    await tester.pumpAndSettle();
    expect(namesIn(tester, 2), contains('panel_test.dart'), reason: 'содержимое встало справа');
  });

  testWidgets('курсор постоял на каталоге — вид раскрыл его сам', (tester) async {
    final runtime = await open(tester, at: '/home');
    final panel = runtime.app.left;

    panel.setCursorToName('test');
    await tester.pump();
    expect(tester.widgetList(columns()).length, 2, reason: 'сразу ничего не раскрывается');

    await tester.pump(ColumnsView.holdBeforeOpen);
    await tester.pumpAndSettle();

    expect(namesIn(tester, 2), contains('panel_test.dart'), reason: 'придержка показала содержимое');
  });

  testWidgets('раскрытое видом сворачивается, когда курсор ушёл', (tester) async {
    final runtime = await open(tester, at: '/home');
    final panel = runtime.app.left;

    panel.setCursorToName('test');
    // Первый кадр заводит отсчёт, и только следующий его пропускает: таймер
    // рождается в разметке.
    await tester.pump();
    await tester.pump(ColumnsView.holdBeforeOpen);
    await tester.pumpAndSettle();
    expect(tester.widgetList(columns()).length, 3);

    // Ушли к соседу и вернулись: раскрытое видом убрано за собой, и третий
    // столбец снова ждёт придержки. Иначе неделя прогулок превратит `Cmd-3` в
    // кусты — раскрытое общее с деревом и уезжает в настройки.
    panel.setCursorToName('main.dart');
    await tester.pumpAndSettle();
    panel.setCursorToName('test');
    await tester.pump();

    expect(tester.widgetList(columns()).length, 2, reason: 'вид за собой убрал');
  });

  testWidgets('раскрытое руками остаётся раскрытым', (tester) async {
    final runtime = await open(tester, at: '/home');
    final panel = runtime.app.left;

    Finder row(String name) => find.descendant(of: find.byType(ColumnsView), matching: find.text(name));
    await tester.tap(row('test'));
    await tester.pumpAndSettle();
    await tester.tap(row('test'));
    await tester.pumpAndSettle();
    expect(tester.widgetList(columns()).length, 3);

    panel.setCursorToName('main.dart');
    await tester.pumpAndSettle();
    panel.setCursorToName('test');
    await tester.pump();

    // Сразу, без придержки: это выбор человека, и уход курсора его не отменяет.
    expect(tester.widgetList(columns()).length, 3);
  });

  group('клавиши', () {
    testWidgets('Right раскрывает, второй раз — уводит внутрь', (tester) async {
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      panel.setCursorToName('test');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.name, 'test', reason: 'сперва только раскрылось');
      expect(tester.widgetList(columns()).length, 3);

      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.name, 'panel_test.dart', reason: 'и только потом шаг внутрь');
    });

    testWidgets('Left возвращает к родителю и ничего не сворачивает', (tester) async {
      final runtime = await open(tester, at: '/home/test');
      final panel = runtime.app.left;
      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.name, 'panel_test.dart');

      runtime.commands.dispatch(KeyCombination.parse('Left'));
      await tester.pumpAndSettle();

      expect(panel.currentEntry?.name, 'test', reason: 'вышли к родителю');
      // Столбец справа остаётся: из него только что вышли, и убирать его
      // нажатием «назад» значило бы стирать пройденное.
      expect(namesIn(tester, 2), contains('panel_test.dart'));
    });

    testWidgets('Left в первом столбце молча стоит', (tester) async {
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      panel.setCursorToName('home');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Left'));
      await tester.pumpAndSettle();

      // Корень столбцом не рисуется, вставать на него некуда. И отказаться
      // нельзя: клавишу подхватило бы дерево и свернуло ветвь.
      expect(panel.currentEntry?.name, 'home');
      expect(tester.widgetList(columns()).length, greaterThan(1), reason: 'ничего не свернулось');
    });

    testWidgets('Right на файле ничего не двигает', (tester) async {
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      panel.setCursorToName('main.dart');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();

      expect(panel.currentEntry?.name, 'main.dart');
    });

    testWidgets('Down идёт к соседу по каталогу, а не в чужое поддерево', (tester) async {
      final runtime = await open(tester, at: '/home/lib');
      final panel = runtime.app.left;
      // `lib` раскрыт и стоит выше `test`: по плоскому списку следом за ним
      // идут его дети, а по столбцу — сосед.
      panel.setCursorToName('lib');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pumpAndSettle();

      expect(panel.currentEntry?.name, 'test');
    });

    testWidgets('Home и End ходят по столбцу, а не по списку', (tester) async {
      final runtime = await open(tester, at: '/home/lib');
      final panel = runtime.app.left;
      panel.setCursorToName('test');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Home'));
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.name, 'lib', reason: 'первая строка своего столбца, а не корень');

      runtime.commands.dispatch(KeyCombination.parse('End'));
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.name, 'main.dart', reason: 'последняя строка своего столбца');
    });
  });

  group('сторож порядка привязок', () {
    // Столбцы объявлены раньше дерева и позже комбинированного вида, и цена
    // ошибки здесь невидима: клавиша молча достаётся не тому.
    testWidgets('в дереве Left по-прежнему сворачивает ветвь', (tester) async {
      final runtime = await open(tester, at: '/home/lib');
      final panel = runtime.app.left;
      await panel.setView(TreeView.viewId);
      await tester.pumpAndSettle();
      panel.setCursorToName('lib');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Left'));
      await tester.pumpAndSettle();

      final shown = [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: find.byType(TreeView), matching: find.byType(Text)),
        ))
          text.data,
      ];
      expect(shown, isNot(contains('app.dart')), reason: 'ветвь свернулась');
    });

    testWidgets('в таблице Left уводит в начало списка', (tester) async {
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      await panel.setView(PanelSettings.defaultView);
      await tester.pumpAndSettle();
      panel.setCursorToName('main.dart');
      await tester.pump();

      runtime.commands.dispatch(KeyCombination.parse('Left'));
      await tester.pumpAndSettle();

      expect(panel.cursorIndex, 0);
    });
  });

  testWidgets('знак «дальше вправо» — только у того, в который вошли', (tester) async {
    await open(tester, at: '/home/lib');

    // Шевронов ровно столько, сколько столбцов справа, — по одному на каждое
    // пройденное звено. У прочих каталогов знака нет: он обещал бы то, чего на
    // экране нет. Значок типа рисуется не текстом, так что глифы здесь — это
    // шевроны и только они.
    final chevrons =
        tester
            .widgetList<Text>(find.descendant(of: columns(), matching: find.byType(Text)))
            .where((text) => (text.data ?? '').isNotEmpty && text.data!.codeUnitAt(0) >= 0xE000)
            .length;

    expect(chevrons, 2, reason: 'вошли в `home` и в `lib` — два знака');
  });

  testWidgets('у курсора на файле знака нет: справа ничего', (tester) async {
    final runtime = await open(tester, at: '/home');
    runtime.app.left.setCursorToName('main.dart');
    await tester.pumpAndSettle();

    final chevrons =
        tester
            .widgetList<Text>(find.descendant(of: columns(), matching: find.byType(Text)))
            .where((text) => (text.data ?? '').isNotEmpty && text.data!.codeUnitAt(0) >= 0xE000)
            .length;

    // Один — на `home`, из которого вырос столбец под курсором. У самого файла
    // знака быть не может: показывать справа нечего.
    expect(chevrons, 1);
  });

  testWidgets('пройденное звено — ярким именем, а полоса одна', (tester) async {
    // Курсор на `src`, а выше по пути — `home` и `lib`: путь виден весь, а не
    // только его конец. Тот же приём, каким навигатор комбинированного вида
    // показывает ветвь, чей список виден рядом (`panel-view-combined.md`, §5а):
    // двух курсоров на экране не бывает.
    final runtime = await open(tester, at: '/home/lib/src');
    final colors = FcTheme.of(tester.element(find.byType(ColumnsView))).colors;

    Color? colorOf(String name) {
      // Внутри списков, а не по всему виду: то же имя стоит и в шапке столбца
      // справа — речь про строку.
      final text = tester.widget<Text>(find.descendant(of: columns(), matching: find.text(name)).first);
      return text.style?.color ?? text.textSpan?.style?.color;
    }

    expect(runtime.app.left.currentEntry?.name, 'src');
    expect(colorOf('home'), colors.cursorText, reason: 'пройденное звено — ярким');
    expect(colorOf('lib'), colors.cursorText);
    expect(colorOf('test'), isNot(colors.cursorText), reason: 'сосед по столбцу — обычным');

    // Полоса курсора одна на все столбцы, и она у той строки, где курсор.
    final painted =
        tester
            .widgetList<DecoratedBox>(
              find.descendant(of: find.byType(ColumnsView), matching: find.byType(DecoratedBox)),
            )
            .map((box) => (box.decoration as BoxDecoration).color)
            .toList();
    expect(painted.where((color) => color == colors.cursorBackground).length, 1);
  });
}
