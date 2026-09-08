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

/// Дерево с содержимым рядом (`docs/spec/panel-view-combined.md`).
///
/// Столбцы — две сессии одного слота, и курсор стоит в той, что показана.
void main() {
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/lib'),
    FakeEntry.directory('/home/lib/src'),
    FakeEntry.file('/home/lib/main.dart', size: 10),
    FakeEntry.directory('/home/test'),
    FakeEntry.file('/home/notes.txt', size: 3),
    FakeEntry.file('/home/test/all_test.dart', size: 4),
  ])..home = '/home';

  AppSettings settingsAt(String path) =>
      AppSettings(left: PanelSettings.defaults(path), right: PanelSettings.defaults(path));

  /// Приложение с левой панелью в комбинированном виде.
  Future<AppRuntime> open(WidgetTester tester, {String path = '/home'}) async {
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settingsAt(path));
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
  List<Panel> columns(AppRuntime runtime) => runtime.app.panelsAt(ViewportPosition.left);

  Panel tree(AppRuntime runtime) => columns(runtime).first;

  Panel list(AppRuntime runtime) => columns(runtime)[1];

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

  testWidgets('уход на другой вид закрывает второй столбец', (tester) async {
    final runtime = await open(tester);
    await settle(tester);

    runtime.commands.dispatch(KeyCombination.parse('Cmd-1'));
    await tester.pumpAndSettle();

    expect(columns(runtime).length, 1, reason: 'слот схлопнулся');
    expect(runtime.app.left.view, 'table');
  });
}
