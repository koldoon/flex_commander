import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Источник, чтение которого идёт заметное время.
///
/// На подставном дереве обход кончается мгновенно, а проверять надо то, что
/// происходит, **пока он идёт**.
class _SlowProvider extends InMemoryTreeProvider {
  _SlowProvider(super.entries);

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.listChildren(dir);
  }
}

/// Окно поиска проверяется целиком: от клавиши до найденного в панели.
void main() {
  late AppController app;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/lib'),
      FakeEntry.directory('/home/lib/src'),
      FakeEntry.file('/home/main.dart', size: 1),
      FakeEntry.file('/home/lib/main.dart', size: 1),
      FakeEntry.file('/home/lib/src/util.dart', size: 1),
      FakeEntry.file('/home/lib/build.sh', size: 1, executable: true),
      FakeEntry.file('/home/readme.md', size: 1),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
  });

  // Именно поле окна: внизу экрана стоит ещё и командная строка.
  final input = find.descendant(
    of: find.byType(FindFilesForm),
    matching: find.byWidgetPredicate((widget) => widget is TextField && widget.enabled != false),
  );

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(802, 621)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  Future<void> openWindow(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
  }

  /// Набирает маску и запускает поиск **настоящим `Enter`**, дождавшись обхода.
  ///
  /// Не `receiveAction(done)`: тот дёргает `onSubmitted` поля напрямую и минует
  /// то, что делает живое нажатие. А в открытом окне `Enter` разбирает рама и
  /// отдаёт окну — и ровно этого у окна поиска не было: тесты проходили, а
  /// человек не мог начать поиск вовсе.
  Future<void> search(WidgetTester tester, String mask) async {
    await tester.enterText(input, mask);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FcButton, label));
    await tester.pumpAndSettle();
  }

  testWidgets('Alt-F7 открывает окно: поле маски в фокусе, каталог показан', (tester) async {
    await pumpApp(tester);

    await openWindow(tester);

    expect(find.text('Find files'), findsWidgets);
    final editable = tester.widget<EditableText>(find.descendant(of: input, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
    // Где ищем — видно, и правится это только переходом панели.
    expect(find.text('/home'), findsWidgets);
  });

  testWidgets('фокус достаётся маске, даже когда ввод был у командной строки', (tester) async {
    await pumpApp(tester);
    // Ввод у строки внизу — обычное состояние в режиме `mc`. Строка возвращает
    // себе фокус, когда область числится за ней, и делает это в тот же кадр, в
    // который открывается окно: маска обязана победить в этой гонке.
    app.view.setFocus(ViewportPosition.bottom);
    await tester.pumpAndSettle();

    await openWindow(tester);

    final editable = tester.widget<EditableText>(find.descendant(of: input, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('маска отбирает по всему дереву, а не по одному каталогу', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await search(tester, '*.dart');

    expect(find.text('Found: 3'), findsOneWidget);
    // Раскладка `mc`: каталог заголовком, находки под ним.
    expect(find.text('util.dart'), findsOneWidget);
    expect(find.text('/home/lib/src'), findsOneWidget);
  });

  testWidgets('кнопка «OK» ищет то же, что и Enter', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    // Пока маски нет, начинать нечего — и кнопка это показывает.
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'OK')).onPressed, isNull);

    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();
    await press(tester, 'OK');

    expect(find.text('Found: 3'), findsOneWidget);
  });

  testWidgets('фазы: сперва спрашивают, потом показывают', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    // Первое окно — только вопрос: поля и две кнопки.
    expect(find.byType(FindFilesForm), findsOneWidget);
    expect(find.byType(FindFilesResults), findsNothing);
    expect(find.widgetWithText(FcButton, 'OK'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'To panel'), findsNothing);

    await search(tester, '*.dart');

    // Второе — только находки: полей ввода в нём нет вовсе.
    expect(find.byType(FindFilesForm), findsNothing, reason: 'параметры своё отработали');
    expect(find.byType(FindFilesResults), findsOneWidget);
    expect(find.text('File name:'), findsNothing);
    expect(find.widgetWithText(FcButton, 'To panel'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'Again'), findsOneWidget);
  });

  testWidgets('«Again» возвращает вопрос с прежней маской', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');

    await press(tester, 'Again');

    expect(find.byType(FindFilesForm), findsOneWidget);
    expect(find.byType(FindFilesResults), findsNothing);
    // Маска на месте: спрашивают заново, а не с чистого листа.
    expect(tester.widget<TextField>(input).controller!.text, '*.dart');
  });

  testWidgets('пока идёт обход, «ничего не нашлось» не говорится', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    // В окне параметров об этом речи нет вовсе: там ещё спрашивают.
    expect(find.text('Nothing found'), findsNothing);

    await search(tester, '*.zip');

    expect(find.text('Nothing found'), findsOneWidget);
    expect(find.text('Found: 0'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('«во вложенных» выключается — и находится только своё', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await tester.tap(find.text('Find recursively'));
    await tester.pumpAndSettle();
    await search(tester, '*.dart');

    expect(find.text('Found: 1'), findsOneWidget);
  });

  testWidgets('«To panel» делает найденное содержимым панели', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');

    await press(tester, 'To panel');

    expect(app.left.source.scheme, SourceInfo.foundScheme);

    // Деревом, а не кучей: видно, где что нашлось. Вид просит сам источник, и
    // раскрыто оно сразу — иначе находки прятались бы за нажатиями
    // (`docs/spec/file-search.md`, §4).
    expect(app.left.view, TreeView.viewId);
    expect(
      [for (final entry in app.left.entries) '${'  ' * entry.level}${entry.name}'],
      // В порядке обхода, а не по алфавиту: список растёт по ходу поиска, и
      // сортировка вставляла бы новое в середину (`docs/spec/file-search.md`, §4).
      ['*.dart', '  main.dart', '  lib', '    main.dart', '    src', '      util.dart'],
    );
    // Окно ушло: смотреть на список удобнее в панели.
    expect(find.widgetWithText(FcButton, 'To panel'), findsNothing);
  });

  testWidgets('«To panel» на середине обхода: поиск виден полоской, список растёт', (tester) async {
    // Живой дефект: окно исчезало сразу, а находки появлялись через несколько
    // секунд — обход-то шёл, и было непонятно, ждать его или нет.
    final slow = _SlowProvider([
      FakeEntry.directory('/home'),
      for (var i = 0; i < 30; i++) ...[
        FakeEntry.directory('/home/d$i'),
        FakeEntry.file('/home/d$i/found.dart', size: 1),
      ],
    ])..home = '/home';
    app = (await testApp(provider: slow, modules: featureModules())).app;

    await pumpApp(tester);
    await openWindow(tester);
    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
    // Ждём первых находок: отдавать панели пустоту команда отказывается.
    for (var i = 0; i < 40 && state.found.length < 3; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(state.found, isNotEmpty, reason: 'что-то уже нашлось');
    expect(state.busy, isTrue, reason: 'стенд ни о чём, если обход уже кончился');

    // Не нажатием: `pumpAndSettle` внутри него дождался бы конца обхода, а
    // проверяем мы то, что происходит, **пока он идёт**.
    await state.toPanel();
    await tester.pump();

    expect(app.left.source.scheme, SourceInfo.foundScheme, reason: 'находки уже в панели');
    expect(app.operations.at(ViewportPosition.left), hasLength(1), reason: 'а поиск виден полоской');
    final first = app.left.entries.length;
    expect(first, lessThan(61), reason: 'стенд ни о чём, если к этому мигу нашлось всё');

    // Обход идёт дальше, и панель прибавляет находки по ходу дела.
    for (var i = 0; i < 40 && state.busy; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(state.busy, isFalse, reason: 'обход кончился');
    await tester.pump(const Duration(milliseconds: 120));

    expect(app.left.entries.length, greaterThan(first), reason: 'список вырос, пока шёл обход');
    expect(app.left.entries.where((entry) => entry.name == 'found.dart'), hasLength(30));
  });

  testWidgets('панель уже деревом — находки всё равно раскрыты', (tester) async {
    // Живой дефект: вид уже стоял древесным, второй раз он ни о чём не просит,
    // и находки показывались списком своего корня — «..» и одна ветвь, которая
    // не раскрывалась (`docs/spec/panel-node-list.md`, §11).
    await pumpApp(tester);
    await app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();
    // Курсор на ветви внутри `/home` — оттуда и ищем: в дереве каталог панели
    // идёт за курсором.
    app.left.setCursorToName('lib');
    await tester.pumpAndSettle();
    expect(app.left.currentPath, '/home', reason: 'стенд ни о чём, если ищем не оттуда');

    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    expect(app.left.rows, RowsKind.tree);
    expect(
      [for (final entry in app.left.entries) '${'  ' * entry.level}${entry.name}'],
      // В порядке обхода, а не по алфавиту: список растёт по ходу поиска, и
      // сортировка вставляла бы новое в середину (`docs/spec/file-search.md`, §4).
      ['*.dart', '  main.dart', '  lib', '    main.dart', '    src', '      util.dart'],
    );
  });

  testWidgets('из найденного деревом возвращаются в каталог поиска', (tester) async {
    await pumpApp(tester);
    await app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();
    app.left.setCursorToName('lib');
    await tester.pumpAndSettle();

    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    await app.left.goUp();
    await tester.pumpAndSettle();

    // Не в корень диска: дерево строится от корня источника, и уход из находок
    // приводил панель туда — курсор оставался на первой строке.
    expect(app.left.source.scheme, isNot(SourceInfo.foundScheme));
    expect(app.left.currentEntry?.path, '/home', reason: 'курсор на ветви каталога, откуда искали');
  });

  testWidgets('Alt-O на ветви находок открывает настоящий каталог', (tester) async {
    // Живой дефект: ветвь находок — виртуальная, и её собственный адрес
    // соседней панели ни о чём не говорит: команда молчала.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    app.left.setCursorToName('lib');
    await tester.pumpAndSettle();
    expect(app.left.currentEntry?.realPath, '/home/lib', reason: 'ветвь знает свой настоящий каталог');

    await app.commands.create('panel.openInOther')!.executeWith();
    await tester.pumpAndSettle();

    expect(app.right.currentPath, '/home/lib');
  });

  testWidgets('в найденном видна колонка пути, а раскладка панели цела', (tester) async {
    await pumpApp(tester);
    final before = app.left.columns;
    expect(before.find(FsColumns.path)?.visible, isFalse, reason: 'в обычном каталоге путь у всех один');

    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    // Иначе список нечитаем: `main.dart` в нём два, и различает их только это.
    expect(app.left.columns.find(FsColumns.path)?.visible, isTrue);

    // Дерево говорит это ветвями, а колонку видно в таблице — и посмотреть
    // находки таблицей человек волен: просьба источника не запрет.
    await app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(FileTable).first, matching: find.text('/home')),
      findsWidgets,
      reason: 'в таблице путь находки стоит колонкой',
    );

    // Раскладку просит источник, и уходит она вместе с ним: настройку панели
    // это не переписывает.
    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.columns.find(FsColumns.path)?.visible, isFalse);
  });

  testWidgets('правка колонок в находках не переписывает настройку панели', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    // То же самое делает заголовок таблицы, когда в нём двигают или
    // переключают колонку. На экране в этот момент раскладка **источника**, и
    // записать её в настройки панели значило бы оставить её там навсегда:
    // поймано живьём — панель после находок показывала колонку пути в любом
    // каталоге, и убрать её было нечем.
    app.left.setColumnLayout(app.left.columns);
    await tester.pumpAndSettle();

    await app.left.goUp();
    await tester.pumpAndSettle();

    expect(app.left.source.scheme, isNot(SourceInfo.foundScheme));
    expect(app.left.columns.find(FsColumns.path)?.visible, isFalse, reason: 'колонка пути ушла вместе с находками');
  });

  testWidgets('колонку, которой просит источник, человек может погасить', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');
    expect(app.left.columns.find(FsColumns.path)?.visible, isTrue);

    // Флажок этой колонки стоит в окне вида наравне с прочими, и нажатие, от
    // которого ничего не происходит, — ошибка, а не защита настроек. Просьба
    // источника это умолчание, как и его вид с порядком.
    await app.left.setColumnLayout(app.left.columns.toggleVisible(FsColumns.path));
    await tester.pumpAndSettle();
    expect(app.left.columns.find(FsColumns.path)?.visible, isFalse);

    // Зажгли обратно — просьба снова в силе.
    await app.left.setColumnLayout(app.left.columns.toggleVisible(FsColumns.path));
    await tester.pumpAndSettle();
    expect(app.left.columns.find(FsColumns.path)?.visible, isTrue);
  });

  testWidgets('отмена просьбы живёт не дольше самого источника', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    await app.left.setColumnLayout(app.left.columns.toggleVisible(FsColumns.path));
    await tester.pumpAndSettle();
    expect(app.left.columns.find(FsColumns.path)?.visible, isFalse);

    // Ушли и вернулись: источник просит заново, а погашенное человеком в
    // настройках панели не осело — там его и не было.
    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.columns.find(FsColumns.path)?.visible, isFalse, reason: 'в каталоге путь у всех один');

    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    expect(app.left.columns.find(FsColumns.path)?.visible, isTrue);
  });

  testWidgets('обход идёт в глубину: находка прибывает в конец дерева', (tester) async {
    // В ширину находка из глубины приходила позже, а место её — внутри ветви,
    // нарисованной выше: всё, что ниже, съезжало, и список скакал.
    final deep = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/a'),
      FakeEntry.directory('/home/a/inner'),
      FakeEntry.file('/home/a/inner/deep.dart', size: 1),
      FakeEntry.directory('/home/b'),
      FakeEntry.file('/home/b/late.dart', size: 1),
    ])..home = '/home';
    app = (await testApp(provider: deep, modules: featureModules())).app;

    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;

    // Сперва вся ветвь `a` до самого низа, и только потом `b`: в ширину было
    // бы наоборот — `b/late.dart` пришло бы раньше `a/inner/deep.dart`.
    expect(state.found.map((entry) => entry.name), ['deep.dart', 'late.dart']);
  });

  testWidgets('в находках каретки нет: порядок обхода — не сортировка', (tester) async {
    // Живьём каретка над «Tree» читалась как «список отсортирован», хотя он
    // идёт в порядке обхода.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    final icons = FcTheme.of(tester.element(find.byType(TreeView))).icons;
    Finder caret() => find.descendant(
      of: find.byType(TreeView),
      matching: find.byWidgetPredicate(
        (widget) => widget is Icon && (widget.icon == icons.caretUp || widget.icon == icons.caretDown),
      ),
    );

    expect(app.left.sorted, isFalse, reason: 'порядок источника, а не правило панели');
    expect(caret(), findsNothing, reason: 'каретка обещала бы порядок, которого нет');

    // Щёлкнули по заголовку — правило включилось, и каретка появилась.
    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Tree')));
    await tester.pumpAndSettle();
    expect(app.left.sorted, isTrue);
    expect(caret(), findsOneWidget);
  });

  testWidgets('таблицей и кратким находки показываются, не выпадая из них', (tester) async {
    // Живой дефект: курсор стоял на самой находке, и переход к списочному виду
    // уводил панель в каталог **файла** — вернуться в находки было уже нечем.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    app.left.setCursorToName('util.dart');
    await tester.pumpAndSettle();

    await app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();

    // Показана ветвь, в которой находка стоит, — виртуальная, из находок.
    expect(app.left.source.scheme, SourceInfo.foundScheme);
    expect(app.left.entries.map((entry) => entry.name), ['..', 'util.dart']);
    expect(app.left.currentEntry?.name, 'util.dart', reason: 'курсор остался на находке');

    // И «..» ведёт вверх по находкам, а не по диску.
    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.source.scheme, SourceInfo.foundScheme);
    expect(app.left.entries.map((entry) => entry.name), ['..', 'main.dart', 'src']);

    // Краткий вид — то же самое: набор строк тот же, меняется только показ.
    await app.left.setView(BriefView.viewId);
    await tester.pumpAndSettle();
    expect(app.left.source.scheme, SourceInfo.foundScheme);
    expect(app.left.entries.map((entry) => entry.name), ['..', 'main.dart', 'src']);
  });

  testWidgets('F4 над находкой правит её, а над ветвью молчит', (tester) async {
    // Живой дефект: команда спрашивала **панель**, а у списка находок умений
    // нет вовсе — `F4` не работал ни над чем.
    //
    // Источник с содержимым: править можно то, что умеют и отдать, и принять.
    final withBytes = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/lib'),
      FakeEntry.file('/home/lib/util.dart', size: 1),
    ])..home = '/home';
    app = (await testApp(provider: withBytes, modules: featureModules())).app;

    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    final edit = app.commands.create('file.edit')!;
    app.left.setCursorToName('lib');
    await tester.pumpAndSettle();
    expect(edit.isExecutable(CommandContext.of(app)), isFalse, reason: 'ветвь не файл');

    app.left.setCursorToName('util.dart');
    await tester.pumpAndSettle();
    expect(edit.isExecutable(CommandContext.of(app)), isTrue, reason: 'находка — настоящий файл своего источника');
  });

  testWidgets('Enter в таблице находок входит в ветвь, а не ведёт в никуда', (tester) async {
    // Живой дефект: `Enter` забирала команда «перейти к находке», а своего
    // каталога у ветви нет — в таблице и кратком виде войти в неё было нельзя.
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    await app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    expect(app.left.entries.map((entry) => entry.name), ['..', 'main.dart', 'lib']);

    app.left.setCursorToName('lib');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Вошли в ветвь — и остались в находках.
    expect(app.left.source.scheme, SourceInfo.foundScheme);
    expect(app.left.entries.map((entry) => entry.name), ['..', 'main.dart', 'src']);
  });

  testWidgets('Enter в найденном ведёт к файлу, а не открывает его', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    app.left.setCursorToName('util.dart');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(app.left.currentPath, '/home/lib/src');
    expect(app.left.currentEntry?.name, 'util.dart');
  });

  testWidgets('Enter в найденном не запускает исполняемый файл', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.sh');
    await press(tester, 'To panel');

    app.left.setCursorToName('build.sh');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Запускают из каталога панели, а у находок его нет. `Enter` тут значит
    // «покажи, где он лежит».
    expect(app.left.currentPath, '/home/lib');
    expect(app.left.currentEntry?.name, 'build.sh');
  });

  testWidgets('из найденного «..» возвращает прежний каталог', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    await app.left.goUp();
    await tester.pumpAndSettle();

    expect(app.left.source.scheme, isNot(SourceInfo.foundScheme));
    expect(app.left.currentPath, '/home');
  });

  testWidgets('«Go to file» ведёт панель в каталог находки и ставит на неё курсор', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    // Маска не 'util.dart': набранное стоит в поле, и `find.text` нашёл бы
    // сразу два.
    await search(tester, '*.dart');

    // Щелчок выбирает, ведёт — кнопка: так же, как в `mc`, где по списку
    // ходят, а `Chdir` нажимают.
    await tester.tap(find.text('util.dart'));
    await tester.pumpAndSettle();
    await press(tester, 'Go to file');

    expect(app.left.currentPath, '/home/lib/src');
    expect(app.left.currentEntry?.name, 'util.dart');
    // Поиск при этом не пропал: сходить к одной находке — не повод потерять
    // остальные.
    expect(app.operations.at(ViewportPosition.left), hasLength(1));
  });

  testWidgets('таблица находок не меняет размера, пока они прибывают', (tester) async {
    // Список, растущий по ходу работы, дёргал бы окно под курсором на каждой
    // пачке. Окно пошире: в тесном ряд кнопок ужимается целиком (`FittedBox` в
    // `FcDialogActions`), а от его высоты едет и всё остальное.
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');

    final table = tester.getRect(find.byType(FoundTable));
    final window = tester.getRect(find.byType(FindFilesResults));
    expect(find.text('util.dart'), findsOneWidget);

    // Ещё один поиск в том же окне: находок другое число, размеры те же.
    await press(tester, 'Again');
    await search(tester, '*.md');

    expect(tester.getRect(find.byType(FoundTable)), table, reason: 'таблица там же и того же размера');
    expect(tester.getRect(find.byType(FindFilesResults)), window, reason: 'и окно не поехало');
  });

  testWidgets('находки красятся как в панели, заголовок каталога — всегда белым', (tester) async {
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');

    const colors = DefaultColors();
    // Строки списка по порядку: имя и цвет, каким оно набрано. Имена в
    // находках повторяются (`main.dart` лежит в двух каталогах) — различает их
    // только место в списке.
    List<(String, Color?)> rows() => [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byType(FoundTable), matching: find.byType(Text)),
      ))
        (text.data ?? '', text.style?.color),
    ];

    // Курсора ещё нет: обход только кончился, по списку не ходили.
    expect(rows(), [
      ('/home', colors.pathText),
      ('main.dart', colors.rowText),
      ('/home/lib', colors.pathText),
      ('main.dart', colors.rowText),
      ('/home/lib/src', colors.pathText),
      ('util.dart', colors.rowText),
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(rows(), [
      ('/home', colors.pathText),
      ('main.dart', colors.cursorText),
      ('/home/lib', colors.pathText),
      ('main.dart', colors.rowText),
      ('/home/lib/src', colors.pathText),
      ('util.dart', colors.rowText),
    ], reason: 'под курсором — как в панели, белым');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Курсор ушёл дальше: белой стала следующая находка, а заголовки не
    // шелохнулись — курсор по ним не ходит вовсе.
    expect(rows(), [
      ('/home', colors.pathText),
      ('main.dart', colors.rowText),
      ('/home/lib', colors.pathText),
      ('main.dart', colors.cursorText),
      ('/home/lib/src', colors.pathText),
      ('util.dart', colors.rowText),
    ]);
  });

  testWidgets('тысяча находок — строк собрано столько, сколько видно', (tester) async {
    // То, ради чего таблица своя: общий список окон собирает все строки разом,
    // и на тысячах находок приложение вставало намертво. Здесь строится только
    // видимое.
    final many = <FakeEntry>[FakeEntry.directory('/big')];
    for (var i = 0; i < 1000; i++) {
      many.add(FakeEntry.file('/big/file$i.dart', size: 1));
    }
    app =
        (await testApp(
          provider: InMemoryTreeProvider(many),
          modules: featureModules(),
          settings: AppSettings(left: PanelSettings.defaults('/big'), right: PanelSettings.defaults('/big')),
        )).app;

    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
    expect(state.found, hasLength(1000), reason: 'нашлось всё');
    expect(find.text('Found: 1000'), findsOneWidget);

    // А построено — по числу видимых строк, а не по числу находок.
    final built = tester.widgetList(find.descendant(of: find.byType(FoundTable), matching: find.byType(Row))).length;
    expect(built, lessThan(50), reason: 'список ленивый: строк собрано столько, сколько влезло в обзор');
  });

  testWidgets('перерисовок меньше, чем находок', (tester) async {
    // Уведомление на каждую находку означало перерисовку окна на каждый файл, а
    // вместе с ней — сборку всего списка заново. Отсюда и «зависло»: работа
    // шла, но кадров между ней не оставалось.
    final many = <FakeEntry>[FakeEntry.directory('/big')];
    for (var i = 0; i < 300; i++) {
      many.add(FakeEntry.file('/big/file$i.dart', size: 1));
    }
    app =
        (await testApp(
          provider: InMemoryTreeProvider(many),
          modules: featureModules(),
          settings: AppSettings(left: PanelSettings.defaults('/big'), right: PanelSettings.defaults('/big')),
        )).app;

    await pumpApp(tester);
    await openWindow(tester);

    final state = tester.widget<FindFilesForm>(find.byType(FindFilesForm)).state;
    var redraws = 0;
    state.addListener(() => redraws++);

    await search(tester, '*.dart');

    expect(state.found, hasLength(300));
    expect(redraws, lessThan(50), reason: 'сообщений о находках 300, а перерисовок — единицы');
  });

  group('фон', () {
    testWidgets('«Background» убирает окно, а работа остаётся полоской', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);
      await search(tester, '*.dart');

      // Кнопка жива, только пока есть что оставлять идти.
      final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
      expect(state.busy, isFalse, reason: 'на подставном дереве обход кончается мгновенно');

      // Полоска у законченного поиска всё равно есть: результат и есть вся его
      // работа, и выбросить её молча нельзя.
      state.toBackground();
      await tester.pumpAndSettle();

      expect(find.byType(FindFilesResults), findsNothing, reason: 'окно ушло');
      expect(app.operations.at(ViewportPosition.left), hasLength(1), reason: 'а работа осталась');
      expect(find.textContaining('Find "*.dart"'), findsOneWidget, reason: 'полоска называет поиск');
      // Той же строкой, что и окно находок: итог у работы один, и говорить его
      // двумя разными способами незачем.
      expect(find.text('Found: 3'), findsOneWidget, reason: 'и говорит, чем он кончился');
    });

    testWidgets('щелчок по полоске возвращает то же окно с теми же находками', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);
      await search(tester, '*.dart');
      tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state.toBackground();
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Find "*.dart"'));
      await tester.pumpAndSettle();

      expect(find.byType(FindFilesResults), findsOneWidget);
      expect(find.text('Found: 3'), findsOneWidget, reason: 'находки те же, искать заново не пришлось');
      expect(app.operations.at(ViewportPosition.left), isEmpty, reason: 'из фона работа вернулась');
    });

    testWidgets('крестик у идущего поиска его останавливает, не открывая окна', (tester) async {
      // Живой дефект: крестик просил прерваться, работа переспрашивала, и ради
      // вопроса ей возвращалось окно — остановить фоновый поиск было нельзя.
      final slow = _SlowProvider([
        FakeEntry.directory('/home'),
        for (var i = 0; i < 30; i++) ...[
          FakeEntry.directory('/home/d$i'),
          FakeEntry.file('/home/d$i/found.dart', size: 1),
        ],
      ])..home = '/home';
      app = (await testApp(provider: slow, modules: featureModules())).app;

      await pumpApp(tester);
      await openWindow(tester);
      await tester.enterText(input, '*.dart');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
      for (var i = 0; i < 40 && state.found.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(state.busy, isTrue, reason: 'стенд ни о чём, если обход кончился');

      state.toBackground();
      await tester.pump();
      expect(app.operations.at(ViewportPosition.left), hasLength(1));

      await tester.tap(find.text('✕'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(app.view.dialogs, isEmpty, reason: 'окно находок не выдёргивается');
      expect(app.operations.at(ViewportPosition.left), isEmpty, reason: 'работы не стало');
      expect(state.busy, isFalse, reason: 'обход прерван');
    });

    testWidgets('крестик у законченного поиска его забывает', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);
      await search(tester, '*.dart');
      tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state.toBackground();
      await tester.pumpAndSettle();

      await tester.tap(find.text('✕'));
      await tester.pumpAndSettle();

      expect(app.operations.at(ViewportPosition.left), isEmpty);
      expect(find.byType(FindFilesResults), findsNothing, reason: 'забыли — и не открылось');
    });

    testWidgets('поисков может идти сколько угодно', (tester) async {
      await pumpApp(tester);
      for (final mask in ['*.dart', '*.md']) {
        await openWindow(tester);
        await search(tester, mask);
        tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state.toBackground();
        await tester.pumpAndSettle();
      }

      // По полоске на каждый — ровно как у копирований.
      expect(app.operations.at(ViewportPosition.left), hasLength(2));
      expect(find.textContaining('Find "*.dart"'), findsOneWidget);
      expect(find.textContaining('Find "*.md"'), findsOneWidget);
    });
  });

  testWidgets('Esc закрывает окно, ничего не тронув', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Find files'), findsNothing);
    expect(app.left.currentPath, '/home');
  });
}
