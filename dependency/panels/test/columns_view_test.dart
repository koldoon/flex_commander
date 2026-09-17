import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets('перезапуск возвращает цепочку и курсор', (tester) async {
    // Так приложение и стартует: вид, каталог, раскрытое и строка курсора —
    // всё из настроек (`docs/spec/panel-view-columns.md`, §8а).
    final settings = AppSettings(
      // Каталогом записан **корень**: у древесных видов панель стоит на корне
      // источника, а где человек на самом деле, говорит строка курсора.
      left: PanelSettings(
        path: '/',
        view: ColumnsView.viewId,
        expanded: ['/', '/home', '/home/lib'],
        cursorPath: '/home/lib/app.dart',
      ),
      right: PanelSettings.defaults('/home'),
    );
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settings);
    await runtime.app.start();
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    expect(runtime.app.left.currentEntry?.path, '/home/lib/app.dart', reason: 'курсор там, где его оставили');
    expect(tester.widgetList(columns()).length, 3, reason: 'и цепочка та же');
  });

  testWidgets('место под следующий столбец отведено заранее', (tester) async {
    // Смысл вида в том, чтобы содержимое было видно **до** перехода курсора, а
    // лента не дёргалась от появления и пропажи столбца.
    await open(tester, at: '/home');
    final shown = tester.widgetList(columns()).length;

    final lane = tester.getSize(find.descendant(of: find.byType(ColumnsView), matching: find.byType(Row)).first);
    final width = PanelsSettings.defaultColumnWidth.toDouble();

    expect(lane.width, greaterThanOrEqualTo((shown + 1) * width), reason: 'лишний столбец места — про запас');
  });

  group('лента', () {
    /// Насколько лента промотана вбок.
    double ribbon(WidgetTester tester) =>
        tester
            .widget<Scrollable>(find.descendant(of: find.byType(ColumnsView), matching: find.byType(Scrollable)).first)
            .controller!
            .offset;

    testWidgets('ходьба по столбцу ленту не двигает', (tester) async {
      // Узкая панель: цепочка в неё не помещается, и ехать ленте есть куда.
      final runtime = await open(tester, at: '/home', size: const Size(700, 600));
      final panel = runtime.app.left;
      panel.setCursorToName('lib');
      await tester.pump();
      final was = ribbon(tester);

      // Придержка раскрывает соседний каталог — столбец справа появляется…
      await tester.pump(ColumnsView.holdBeforeOpen);
      await tester.pumpAndSettle();
      expect(tester.widgetList(columns()).length, 3);

      // …но курсор шёл вниз, а не вбок: лента обязана стоять.
      expect(ribbon(tester), was, reason: 'глазу нужна опора');

      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pumpAndSettle();
      expect(ribbon(tester), was);
    });

    testWidgets('после хода вбок место под содержимое остаётся видно', (tester) async {
      // Иначе придержка раскроет каталог в нише, которой не видно, — и
      // содержимое опять придётся открывать вслепую.
      // Панель шириной в два столбца с запасом: в неё помещается и столбец с
      // курсором, и место под содержимое.
      final runtime = await open(tester, at: '/home', size: const Size(1120, 600));
      final panel = runtime.app.left;
      panel.setCursorToName('lib');
      await tester.pump();
      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();
      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.path, '/home/lib/src');

      final lane = tester.getRect(find.byType(ColumnsView));
      final width = PanelsSettings.defaultColumnWidth.toDouble();
      final current = tester.getRect(columns().at(2));

      // Справа от текущего столбца остаётся место шириной в столбец — там и
      // появится содержимое.
      expect(lane.right - current.right, greaterThanOrEqualTo(width - 1), reason: 'ниша в поле зрения');
    });

    testWidgets('шаг вправо ленту двигает', (tester) async {
      final runtime = await open(tester, at: '/home', size: const Size(700, 600));
      final panel = runtime.app.left;
      panel.setCursorToName('lib');
      await tester.pump();
      await tester.pump(ColumnsView.holdBeforeOpen);
      await tester.pumpAndSettle();
      final was = ribbon(tester);

      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();

      expect(ribbon(tester), greaterThan(was), reason: 'курсор сменил столбец — лента идёт следом');
    });
  });

  group('пометка', () {
    testWidgets('пометка каталога шагает по столбцу, а не внутрь него', (tester) async {
      // Шаг общей пометки — «следующая строка списка», а у раскрытого каталога
      // это его первое содержимое: пометив каталог, человек оказывался внутри.
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      panel.setCursorToName('lib');
      await tester.pump();
      // Придержка раскрыла каталог — теперь следом за ним в списке стоят его
      // строки.
      await tester.pump(ColumnsView.holdBeforeOpen);
      await tester.pumpAndSettle();
      expect(tester.widgetList(columns()).length, 3);

      runtime.commands.dispatch(KeyCombination.parse('Space'));
      await tester.pumpAndSettle();

      expect(panel.markedPaths, {'/home/lib'}, reason: 'каталог помечен');
      expect(panel.currentEntry?.path, '/home/test', reason: 'курсор шагнул к соседу по каталогу');
    });

    testWidgets('пометка мышью не уводит курсор из столбца', (tester) async {
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      final row = find.descendant(of: find.byType(ColumnsView), matching: find.text('lib'));
      await mouse.addPointer(location: tester.getCenter(row));
      await tester.pump();
      await mouse.down(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 20));
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(panel.markedPaths, {'/home/lib'});
    });
  });

  group('протяжка', () {
    testWidgets('отрезок пометки не выходит за свой столбец', (tester) async {
      // Между `lib` и `main.dart` в списке строк лежит содержимое раскрытого
      // `lib`. По экрану они соседи, по списку — нет, и пометиться это
      // содержимое не должно: невидимая пометка уехала бы в цели `F5`.
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      panel.setCursorToName('lib');
      await tester.pump();
      await tester.pump(ColumnsView.holdBeforeOpen);
      await tester.pumpAndSettle();
      expect(tester.widgetList(columns()).length, 3, reason: 'lib раскрыт');

      Finder row(String name) => find.descendant(of: columns().at(1), matching: find.text(name));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.addPointer(location: tester.getCenter(row('lib')));
      await tester.pump();
      await mouse.down(tester.getCenter(row('lib')));
      await tester.pump(const Duration(milliseconds: 20));
      await mouse.moveTo(tester.getCenter(row('main.dart')));
      await tester.pump(const Duration(milliseconds: 20));
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(panel.markedPaths, {'/home/lib', '/home/test', '/home/main.dart'});
    });
  });

  group('ширина', () {
    /// Ширины столбцов, слева направо, — по самим спискам.
    List<double> widths(WidgetTester tester) => [
      for (final list in columns().evaluate()) tester.getSize(find.byWidget(list.widget)).width,
    ];

    testWidgets('тяга границы меняет только столбец слева от неё', (tester) async {
      await open(tester, at: '/home/lib');
      final was = widths(tester);
      expect(was.length, 3);

      // Граница между первым и вторым столбцами: тянем вправо на 60 точек.
      final lane = tester.getRect(find.descendant(of: find.byType(ColumnsView), matching: find.byType(Row)).first);
      final grip = Offset(lane.left + was[0], lane.center.dy);
      await tester.dragFrom(grip, const Offset(60, 0));
      await tester.pumpAndSettle();

      final now = widths(tester);
      expect(now[0], closeTo(was[0] + 60, 2), reason: 'шире стал тот, у чьего края тянули');
      expect(now[1], was[1], reason: 'соседям это не указ');
      expect(now[2], was[2]);
    });

    testWidgets('новый столбец открывается шириной родителя', (tester) async {
      final runtime = await open(tester, at: '/home');
      final lane = tester.getRect(find.descendant(of: find.byType(ColumnsView), matching: find.byType(Row)).first);
      final was = widths(tester);

      // Подстроили второй столбец…
      await tester.dragFrom(Offset(lane.left + was[0] + was[1] + 1, lane.center.dy), const Offset(-50, 0));
      await tester.pumpAndSettle();
      final narrowed = widths(tester)[1];

      // …и пошли вглубь: третий наследует ширину того, из кого вышли.
      final panel = runtime.app.left;
      panel.setCursorToName('lib');
      await tester.pump();
      runtime.commands.dispatch(KeyCombination.parse('Right'));
      await tester.pumpAndSettle();

      final now = widths(tester);
      expect(now.length, 3);
      expect(now[2], closeTo(narrowed, 1), reason: 'ритм задаёт тот, из кого вышли');
    });
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

    testWidgets('курсор на корне: стрелка заводит его в цепочку', (tester) async {
      // Корень столбцом не рисуется, и курсора на нём не видно. Нажатие всё
      // равно обязано что-то делать: оно заводит курсор в последний столбец.
      final runtime = await open(tester, at: '/home');
      final panel = runtime.app.left;
      panel.setCursorIndex(0);
      await tester.pumpAndSettle();
      expect(panel.currentEntry?.path, '/');

      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pumpAndSettle();

      expect(panel.currentEntry?.path, isNot('/'), reason: 'курсор в столбце, а не в никуда');
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
