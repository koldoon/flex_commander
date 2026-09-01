import 'package:fc_api/fc_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
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

  testWidgets('маска отбирает по всему дереву, а не по одному каталогу', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await search(tester, '*.dart');

    expect(find.text('Found 3 items'), findsOneWidget);
    // Одни имена в плоском списке бесполезны: рядом сказано, откуда каждое.
    expect(find.text('util.dart'), findsOneWidget);
    expect(find.text('lib/src'), findsOneWidget);
  });

  testWidgets('кнопка «Begin» ищет то же, что и Enter', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    // Пока маски нет, начинать нечего — и кнопка это показывает.
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Begin')).onPressed, isNull);

    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();
    await press(tester, 'Begin');

    expect(find.text('Found 3 items'), findsOneWidget);
  });

  testWidgets('кнопки про находки до первого поиска не показываются', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    // Мёртвая кнопка, у которой ещё и смысл неочевиден, — это вопрос без
    // ответа: показывать её до находок незачем.
    expect(find.widgetWithText(FcButton, 'Go to file'), findsNothing);
    expect(find.widgetWithText(FcButton, 'To panel'), findsNothing);
    // И подсказки про `Enter` нет: он значит «сделать» во всех окнах разом.
    expect(find.text('Press Enter to search'), findsNothing);

    await search(tester, '*.dart');

    expect(find.widgetWithText(FcButton, 'Go to file'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'To panel'), findsOneWidget);
  });

  testWidgets('до первого поиска молчит, а не говорит «ничего не нашлось»', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    expect(find.text('Nothing found'), findsNothing);

    await search(tester, '*.zip');

    expect(find.text('Nothing found'), findsOneWidget);
  });

  testWidgets('«во вложенных» выключается — и находится только своё', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await tester.tap(find.text('Look inside subdirectories'));
    await tester.pumpAndSettle();
    await search(tester, '*.dart');

    expect(find.text('Found 1 item'), findsOneWidget);
  });

  testWidgets('«To panel» делает найденное содержимым панели', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');

    await press(tester, 'To panel');

    expect(app.left.provider, isA<SearchResultsProvider>());
    expect(app.left.nodes.map((node) => node.name), containsAll(['main.dart', 'util.dart']));
    // Окно ушло: смотреть на список удобнее в панели.
    expect(find.widgetWithText(FcButton, 'To panel'), findsNothing);
  });

  testWidgets('в найденном видна колонка пути, а раскладка панели цела', (tester) async {
    await pumpApp(tester);
    final before = app.left.columns;
    expect(before.find(FsColumn.path)?.visible, isFalse, reason: 'в обычном каталоге путь у всех один');

    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    // Иначе список нечитаем: `main.dart` в нём два, и различает их только это.
    expect(app.left.columns.find(FsColumn.path)?.visible, isTrue);
    expect(find.text('/home/lib/src'), findsOneWidget);

    // Раскладку просит источник, и уходит она вместе с ним: настройку панели
    // это не переписывает.
    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.columns.find(FsColumn.path)?.visible, isFalse);
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

    expect(app.left.directory?.pathString, '/home/lib/src');
    expect(app.left.currentNode?.name, 'util.dart');
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
    expect(app.left.directory?.pathString, '/home/lib');
    expect(app.left.currentNode?.name, 'build.sh');
  });

  testWidgets('из найденного «..» возвращает прежний каталог', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    await app.left.goUp();
    await tester.pumpAndSettle();

    expect(app.left.provider, isNot(isA<SearchResultsProvider>()));
    expect(app.left.directory?.pathString, '/home');
  });

  testWidgets('«Go to file» ведёт панель в каталог находки и ставит на неё курсор', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    // Маска не 'util.dart': набранное стоит в поле, и `find.text` нашёл бы
    // сразу два.
    await search(tester, '*.dart');

    await tester.tap(find.text('util.dart'));
    await tester.pumpAndSettle();

    expect(app.left.directory?.pathString, '/home/lib/src');
    expect(app.left.currentNode?.name, 'util.dart');
  });

  testWidgets('до поиска между формой и кнопками нет пустой строки', (tester) async {
    // Строка хода работы стоит на своём месте, только когда ей есть что
    // сказать. Пустая занимала место, и между формой и кнопками зияла дыра
    // непонятно подо что.
    await pumpApp(tester);
    await openWindow(tester);

    double gap() =>
        tester.getRect(find.byType(CommandDialogActions)).top -
        tester.getRect(find.text('Include hidden files')).bottom;

    final before = gap();
    final metrics = FcTheme.of(tester.element(find.byType(FindFilesForm))).metrics;
    expect(before, lessThan(metrics.inputHeight), reason: 'лишней строки нет');

    // Искали и не нашли — вот теперь строке есть что сказать.
    await search(tester, '*.zip');

    expect(find.text('Nothing found'), findsOneWidget);
    expect(gap(), greaterThan(before), reason: 'строка появилась только сейчас');
  });

  testWidgets('находок больше, чем показывает список: сказано сколько', (tester) async {
    // Список в окне не ленивый, и тысячи строк собирались бы на каждую
    // перерисовку — из-за этого приложение и вставало. Окно показывает первые,
    // а разглядывать находки идут в панель.
    final many = <FakeEntry>[FakeEntry.directory('/big')];
    for (var i = 0; i < FindFilesState.shownLimit + 50; i++) {
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

    final state = tester.widget<FindFilesForm>(find.byType(FindFilesForm)).state;
    expect(state.found, hasLength(FindFilesState.shownLimit + 50));
    expect(state.shown, hasLength(FindFilesState.shownLimit));
    expect(find.text('Found 250 items, first 200 shown'), findsOneWidget);
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

  testWidgets('Esc закрывает окно, ничего не тронув', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Find files'), findsNothing);
    expect(app.left.directory?.pathString, '/home');
  });
}
