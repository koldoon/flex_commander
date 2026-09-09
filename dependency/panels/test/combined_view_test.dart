import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дерево с содержимым рядом (`docs/spec/panel-view-combined.md`).
///
/// Столбцы — две сессии одного слота, и курсор стоит в той, что показана.
void main() {
  late FakePty pty;

  setUp(() => pty = FakePty());

  InMemoryTreeProvider provider() => InMemoryTreeProvider(
    [
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/lib'),
      FakeEntry.directory('/home/lib/src'),
      FakeEntry.file('/home/lib/main.dart', size: 10),
      FakeEntry.directory('/home/test'),
      FakeEntry.file('/home/notes.txt', size: 3),
      FakeEntry.file('/home/test/all_test.dart', size: 4),
    ],
    null,
    pty,
  )..home = '/home';

  AppSettings settingsAt(String path) =>
      AppSettings(left: PanelSettings.defaults(path), right: PanelSettings.defaults(path));

  /// Приложение с левой панелью в комбинированном виде.
  ///
  /// [lagging] — дверь, придерживающая вести ядра: так ведёт себя порт, и
  /// только так ловятся гонки связки между столбцами.
  Future<AppRuntime> open(WidgetTester tester, {String path = '/home', bool lagging = false}) async {
    final runtime = await testApp(
      provider: provider(),
      modules: featureModules(),
      settings: settingsAt(path),
      door: lagging ? LaggingDoor.new : null,
    );
    await runtime.app.start();
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(CombinedView.viewId);
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Столбцы левой стороны: первый — дерево, второй — список.
  List<Session> columns(AppRuntime runtime) => runtime.app.panelsAt(ViewportPosition.left);

  Session tree(AppRuntime runtime) => columns(runtime).first;

  Session list(AppRuntime runtime) => columns(runtime)[1];

  /// Дать придержанному чтению случиться.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  testWidgets('вид разводит сторону на два столбца', (tester) async {
    final runtime = await open(tester);

    expect(columns(runtime).length, 2, reason: 'столбцы — это две сессии слота');
    expect(find.byType(TreeView), findsOneWidget);
    expect(find.byType(FileTable), findsWidgets);
    // Показана та сессия, в которой стоит курсор: пришли из списка — в нём и
    // остались.
    expect(runtime.app.left, same(list(runtime)));
  });

  testWidgets('в дереве только каталоги', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    final rows = tree(runtime).entries.map((entry) => entry.name).toList();
    expect(rows, isNot(contains('notes.txt')), reason: 'файлы живут в правом столбце');
    expect(rows, contains('home'));
    expect(tree(runtime).rows, RowsKind.branches);
  });

  testWidgets('список догоняет курсор дерева — с придержкой', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    // В дерево и вниз по ветвям: курсор стоит на `home`, под ним `lib`.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, same(tree(runtime)), reason: 'Left из списка уводит в дерево');

    // Шаги — кадрами **без времени**: придержка меряется временем, и
    // `pumpAndSettle` пролистал бы её вместе с ожиданием.
    while (tree(runtime).currentEntry?.name != 'lib') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }

    // Курсор уже там, а список ещё нет: чтение придержано.
    expect(list(runtime).currentPath, '/home');

    await settle(tester);
    expect(list(runtime).currentPath, '/home/lib', reason: 'после придержки список догнал');
  });

  testWidgets('Right раскрывает закрытую ветвь, а на раскрытой уходит в список', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    while (tree(runtime).currentEntry?.name != 'lib') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }
    expect(tree(runtime).currentEntry?.isOpen, isFalse, reason: 'стенд ни о чём, если ветвь уже раскрыта');

    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(tree(runtime).currentEntry?.isOpen, isTrue, reason: 'закрытую — раскрыть');
    expect(runtime.app.left, same(tree(runtime)), reason: 'курсор остался в дереве');

    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, same(list(runtime)), reason: 'раскрытая — уводит в список');
  });

  testWidgets('дерево догоняет список, когда тот входит в каталог', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    list(runtime).setCursorToName('lib');
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(list(runtime).currentPath, '/home/lib');
    expect(tree(runtime).currentEntry?.name, 'lib', reason: 'дерево встало на ту же ветвь');
  });

  testWidgets('курсор в дереве не отбрасывает назад', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();

    // Идём вниз, не дожидаясь придержки: список остаётся на прежнем каталоге,
    // и связка не должна тянуть курсор обратно к нему.
    final names = <String>[];
    for (var step = 0; step < 3; step++) {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
      names.add(tree(runtime).currentEntry?.name ?? '');
    }
    final last = names.last;

    await settle(tester);
    await settle(tester);

    expect(tree(runtime).currentEntry?.name, last, reason: 'курсор остался там, куда его привели: $names');
  });

  testWidgets('пока список читает, курсор дерева не отбрасывает назад', (tester) async {
    // Придержанная дверь: список узнаёт о новом каталоге позже, чем курсор
    // успевает уйти дальше, — ровно как на порту.
    final runtime = await open(tester, lagging: true);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();

    // Шаг, придержка, чтение — и, не дожидаясь вестей, ещё шаг.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pump(const Duration(milliseconds: 200));
    final was = tree(runtime).currentEntry?.name;
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pump();
    final now = tree(runtime).currentEntry?.name;
    expect(now, isNot(was), reason: 'стенд ни о чём, если курсор не сдвинулся');

    // Вести о прежнем каталоге приходят сюда — и не должны ничего двигать.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(tree(runtime).currentEntry?.name, now, reason: 'список — пассажир, а не поводырь');
  });

  testWidgets('знак раскрытия стоит только там, где внутри есть ветви', (tester) async {
    final runtime = await open(tester);
    await settle(tester);
    // Ответы приходят следом за строками: дочитывание идёт в фоне.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    bool branches(String name) => tree(runtime).entries.firstWhere((entry) => entry.name == name).hasBranches;

    expect(branches('lib'), isTrue, reason: 'в lib лежит src');
    expect(branches('test'), isFalse, reason: 'в test одни файлы — раскрывать нечего');
  });

  testWidgets('с ветви без ветвей Right уводит вправо сразу', (tester) async {
    final runtime = await open(tester);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    while (tree(runtime).currentEntry?.name != 'test') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }

    // Знака раскрытия у неё нет — и обещать нажатием то, чего не видно,
    // нельзя: курсор уходит в список с первого раза.
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();

    expect(runtime.app.left, same(list(runtime)));
  });

  testWidgets('дерево держит место, когда курсор ушёл в список', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    /// Цвет имени ветви в дереве.
    Color nameColor(String name) {
      final text = tester.widget<Text>(find.descendant(of: find.byType(TreeView), matching: find.text(name)).first);
      return text.style!.color!;
    }

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    while (tree(runtime).currentEntry?.name != 'lib') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }
    await settle(tester);

    final theme = FcTheme.of(tester.element(find.byType(TreeView)));
    expect(nameColor('lib'), theme.colors.cursorText, reason: 'курсор в дереве — имя на полосе');

    // Курсор ушёл в список: первый `Right` раскрывает ветвь, второй уводит
    // вправо. Полосы в дереве после этого нет, но откуда взялся список —
    // видно по имени.
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(runtime.app.left, same(list(runtime)));

    expect(nameColor('lib'), theme.colors.cursorText, reason: 'место осталось помечено');
    expect(nameColor('test'), theme.colors.rowText, reason: 'а соседние ветви — обычные');
  });

  testWidgets('ушли вправо, не дождавшись списка, — дерево остаётся на месте', (tester) async {
    // Придержанная дверь: список едет к новой ветви дольше, чем человек
    // успевает нажать «вправо».
    final runtime = await open(tester, lagging: true);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    // Встали на `lib` и дождались, чтобы список показал её содержимое.
    while (tree(runtime).currentEntry?.name != 'lib') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }
    await settle(tester);
    await settle(tester);
    expect(list(runtime).currentPath, '/home/lib', reason: 'стенд ни о чём, если список не догнал');

    // Шаг вверх — и сразу вправо, не дожидаясь придержки.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pump(const Duration(milliseconds: 20));
    final wanted = tree(runtime).currentEntry?.name;
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    await settle(tester);
    await settle(tester);

    expect(runtime.app.left, same(list(runtime)), reason: 'курсор ушёл в список');
    expect(tree(runtime).currentEntry?.name, wanted, reason: 'дерево осталось там, куда его привели');
    expect(list(runtime).currentPath, '/home', reason: 'а список догнал ту ветвь, с которой уходили');
  });

  testWidgets('окно выбора вида правит колонки списка', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
    await tester.pumpAndSettle();

    // Настраивать в этом виде есть что у списка: у дерева одних каталогов
    // колонок нет вовсе, и его «Modified (not implemented)» здесь был бы
    // враньём — колонка вполне работает.
    expect(find.text('Modified (not implemented)'), findsNothing);
    final before = list(runtime).columns.columns.firstWhere((column) => column.id == FsColumn.modified).visible;

    // Заголовки колонок в панелях зовутся так же — берём тот, что в окне.
    await tester.tap(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Modified')));
    await tester.pumpAndSettle();

    final after = list(runtime).columns.columns.firstWhere((column) => column.id == FsColumn.modified).visible;
    expect(after, !before, reason: 'флажок правит колонки того столбца, у которого они есть');
  });

  testWidgets('Ctrl-O заводит оболочку там, где стоит показанный столбец', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    // Курсор в списке: оболочка начинает в его каталоге.
    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();
    // Оболочка отвечает на уговор: без этого экран ждёт её до истечения срока.
    AgreeingShell(pty.session).greet();
    await tester.pumpAndSettle();

    expect(pty.session.workingDirectory, list(runtime).currentPath);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Ctrl-O из дерева заводит оболочку в его ветви', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    while (tree(runtime).currentEntry?.name != 'lib') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();
    AgreeingShell(pty.session).greet();
    await tester.pumpAndSettle();

    // Курсор в дереве — оболочка заводится там же, куда пойдёт операция: в
    // ближайшем родителе строки, а не в ней самой
    // (`docs/spec/panel-node-list.md`).
    expect(pty.session.workingDirectory, '/home');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('над файлом в дереве оболочка берёт его каталог', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    // В дереве одних каталогов файлов нет — берём обычное дерево: правило у
    // ветвей общее, а беда была именно над файлом.
    await runtime.app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();
    await settle(tester);
    while (runtime.app.left.currentEntry?.name != 'notes.txt') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();
    AgreeingShell(pty.session).greet();
    await tester.pumpAndSettle();

    expect(pty.session.workingDirectory, '/home', reason: 'каталог файла, а не корень источника');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('возврат из полноэкранного ничего не перечитывает', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    // Ушли в дерево и встали на ветвь, которой список ещё не показывал.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    while (tree(runtime).currentEntry?.name != 'lib') {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
      await tester.pump();
    }
    await settle(tester);
    final at = tree(runtime).currentEntry?.name;
    final shown = list(runtime).currentPath;

    // Терминал во весь экран и обратно: панели **прячут**, а не закрывают.
    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();
    AgreeingShell(pty.session).greet();
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Ctrl-O'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(tree(runtime).currentEntry?.name, at, reason: 'курсор дерева на месте');
    expect(list(runtime).currentPath, shown, reason: 'и список показывает то же');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('шаг списка вверх дерево тоже догоняет', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    // Списком входим внутрь, а потом обратно наверх — тем же `Bsp`, каким
    // ходят в панели.
    list(runtime).setCursorToName('lib');
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(tree(runtime).currentEntry?.name, 'lib', reason: 'стенд ни о чём, если дерево не вошло');

    runtime.commands.dispatch(KeyCombination.parse('Bsp'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(list(runtime).currentPath, '/home');
    expect(tree(runtime).currentEntry?.name, 'home', reason: 'дерево вышло вместе со списком');
  });

  testWidgets('по списку можно выйти доверху, и дерево идёт следом', (tester) async {
    // Начинаем изнутри и идём наверх шаг за шагом, с живыми паузами: придержка
    // между шагами успевает сработать, и связка ловится на гонке.
    final runtime = await open(tester, path: '/home/lib');
    await settle(tester);

    final walked = <String>[];
    for (var step = 0; step < 3; step++) {
      runtime.commands.dispatch(KeyCombination.parse('Bsp'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      walked.add(list(runtime).currentPath);
    }
    await settle(tester);

    // Наверх — и не обратно: дерево, догоняя список, само слежения не заказывает.
    expect(walked, ['/home', '/', '/'], reason: 'шаги: $walked');
    // И навигатор стоит там же, куда пришёл список, а не на ветви, из которой
    // вышли: запомненный курсор — правило списка, не дерева.
    expect(tree(runtime).currentEntry?.name, '/');
  });

  testWidgets('уход окном выбора тоже закрывает второй столбец', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    // Тот же уход, но не клавишей вида, а окном: `Alt-F1`, стрелка на «Tree»,
    // `Enter`.
    runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
    await tester.pumpAndSettle();
    // Стрелкой вверх — на «Tree»: по списку в окне ходит его собственный узел
    // фокуса, а не разбор команд.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await settle(tester);

    expect(runtime.app.left.view, TreeView.viewId);
    expect(columns(runtime).length, 1, reason: 'слот схлопнулся');

    // И `Left` в дереве сворачивает ветвь, а не возвращает второй столбец.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    expect(runtime.app.left.view, TreeView.viewId);
  });

  testWidgets('уход на другой вид закрывает второй столбец', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Cmd-1'));
    await tester.pumpAndSettle();

    expect(columns(runtime).length, 1, reason: 'слот схлопнулся');
    expect(runtime.app.left.view, 'table');
  });
}
