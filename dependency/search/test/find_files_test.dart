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

  testWidgets('таблица находок стоит всегда и не меняет размера', (tester) async {
    // Пустая рамка читается как «сюда придут находки», а не как дыра непонятно
    // подо что. И размер у неё постоянный: список, растущий по ходу работы,
    // дёргал бы окно под курсором на каждой пачке.
    // Окно пошире: в тесном ряд кнопок не влезает и ужимается целиком
    // (`FittedBox` в `CommandDialogActions`), а от его высоты едет и всё
    // остальное — окно стоит по центру экрана.
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);

    final empty = tester.getRect(find.byType(FoundTable));
    final window = tester.getRect(find.byType(FindFilesForm));
    expect(find.text('Nothing found'), findsNothing, reason: 'ещё не искали — и молчим');

    await search(tester, '*.dart');

    expect(find.text('util.dart'), findsOneWidget);
    expect(tester.getRect(find.byType(FoundTable)), empty, reason: 'таблица там же и того же размера');
    expect(tester.getRect(find.byType(FindFilesForm)), window, reason: 'и окно не поехало');
  });

  testWidgets('искали и не нашли — таблица говорит об этом сама', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await search(tester, '*.zip');

    expect(find.text('Nothing found'), findsOneWidget);
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

    final state = tester.widget<FindFilesForm>(find.byType(FindFilesForm)).state;
    expect(state.found, hasLength(1000), reason: 'нашлось всё');
    expect(find.text('Found 1000 items'), findsOneWidget);

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

  testWidgets('Esc закрывает окно, ничего не тронув', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Find files'), findsNothing);
    expect(app.left.directory?.pathString, '/home');
  });
}
