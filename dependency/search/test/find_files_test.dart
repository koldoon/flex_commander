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

    // Щелчок выбирает, ведёт — кнопка: так же, как в `mc`, где по списку
    // ходят, а `Chdir` нажимают.
    await tester.tap(find.text('util.dart'));
    await tester.pumpAndSettle();
    await press(tester, 'Go to file');

    expect(app.left.directory?.pathString, '/home/lib/src');
    expect(app.left.currentNode?.name, 'util.dart');
    // Поиск при этом не пропал: сходить к одной находке — не повод потерять
    // остальные.
    expect(app.operations.at(ViewportPosition.left), hasLength(1));
  });

  testWidgets('таблица находок не меняет размера, пока они прибывают', (tester) async {
    // Список, растущий по ходу работы, дёргал бы окно под курсором на каждой
    // пачке. Окно пошире: в тесном ряд кнопок ужимается целиком (`FittedBox` в
    // `CommandDialogActions`), а от его высоты едет и всё остальное.
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
      expect(find.text('Found 3'), findsOneWidget, reason: 'и говорит, чем он кончился');
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
    expect(app.left.directory?.pathString, '/home');
  });
}
