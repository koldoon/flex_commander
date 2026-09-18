import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

/// То же, но с байтами: `F3` и `F4` над находкой читают файл.
class _SlowContentProvider extends InMemoryContentProvider {
  _SlowContentProvider(super.entries);

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

  // Именно поле маски: в окне живых полей теперь несколько (исключения, размер,
  // дата), а внизу экрана стоит ещё и командная строка. Маска — то поле, ради
  // которого окно и открывают, и фокус оно просит себе само.
  final input = find.descendant(
    of: find.byType(FindFilesForm),
    matching: find.byWidgetPredicate((widget) => widget is TextField && widget.autofocus),
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

  group('условия отбора', () {
    /// Поле по подсказке-образцу: живых полей в окне несколько.
    Finder fieldWithHint(String hint) => find.descendant(
      of: find.byType(FindFilesForm),
      matching: find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == hint),
    );

    /// Кнопка `OK` — та, что запускает обход.
    FcButton okButton(WidgetTester tester) => tester.widget<FcButton>(find.widgetWithText(FcButton, 'OK'));

    testWidgets('переключатель читает набранное выражением', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      // Маской `main\.dart$` не совпадёт ни с чем: в маске это просто имя.
      await tester.enterText(input, r'main\.dart$');
      await tester.pumpAndSettle();
      await tester.tap(find.text('.*'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsWidgets, reason: 'прочитано выражением');
    });

    testWidgets('неверное выражение не даёт искать и говорит об этом', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      await tester.enterText(input, '*.dart');
      await tester.pumpAndSettle();
      expect(okButton(tester).onPressed, isNotNull, reason: 'маской это законно');

      await tester.tap(find.text('.*'));
      await tester.pumpAndSettle();

      expect(find.text('The expression is not understood'), findsOneWidget, reason: 'сказано у поля, а не в отказе');
      expect(okButton(tester).onPressed, isNull, reason: 'искать нечем');
    });

    testWidgets('исключённый каталог в находки не попадает', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      await tester.enterText(fieldWithHint('node_modules;.git'), 'src');
      await tester.pumpAndSettle();
      await search(tester, '*.dart');

      expect(find.text('main.dart'), findsWidgets);
      expect(find.text('util.dart'), findsNothing, reason: 'он лежит в `src`');
    });

    testWidgets('регистр различается по флажку', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      // Слева — флажок имени, справа такой же у содержимого: свой у каждого.
      await tester.tap(find.text('Case sensitive').first);
      await tester.pumpAndSettle();
      await search(tester, '*.DART');

      expect(find.text('main.dart'), findsNothing, reason: 'регистр теперь важен');
    });

    testWidgets('неразобранный размер не даёт искать', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      await tester.enterText(input, '*.dart');
      await tester.pumpAndSettle();
      await tester.enterText(fieldWithHint('500k'), 'много');
      await tester.pumpAndSettle();

      expect(okButton(tester).onPressed, isNull);

      await tester.enterText(fieldWithHint('500k'), '1k');
      await tester.pumpAndSettle();
      expect(okButton(tester).onPressed, isNotNull);
    });

    testWidgets('содержимое отбирает находки', (tester) async {
      // Своё дерево: у этого поиска байты решают всё, а обычный стенд их не
      // отдаёт.
      final files = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/found.dart', content: utf8.encode('// TODO разобраться\n')),
        FakeEntry.file('/home/clean.dart', content: utf8.encode('всё сделано\n')),
      ]);
      final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: files, modules: featureModules(), settings: settings)).app;

      await pumpApp(tester);
      await openWindow(tester);

      await tester.enterText(fieldWithHint('TODO'), 'TODO');
      await tester.pumpAndSettle();
      await search(tester, '*.dart');

      expect(find.text('found.dart'), findsWidgets);
      expect(find.text('clean.dart'), findsNothing, reason: 'в нём такого нет');
    });

    testWidgets('неверное выражение содержимого не даёт искать', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      await tester.enterText(input, '*.dart');
      await tester.pumpAndSettle();
      await tester.enterText(fieldWithHint('TODO'), 'TODO(');
      await tester.pumpAndSettle();
      expect(okButton(tester).onPressed, isNotNull, reason: 'строкой это законно');

      // Второй переключатель `.*` — у содержимого.
      await tester.tap(find.text('Regular expression'));
      await tester.pumpAndSettle();

      expect(find.text('The expression is not understood'), findsWidgets);
      expect(okButton(tester).onPressed, isNull);
    });

    testWidgets('выражение и любые кодировки гасят друг друга', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      await tester.tap(find.text('All charsets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regular expression'));
      await tester.pumpAndSettle();

      final flags = tester.widgetList<FcCheckbox>(find.byType(FcCheckbox)).toList();
      final charsets = flags.firstWhere((flag) => flag.label == 'All charsets');
      final regexp = flags.firstWhere((flag) => flag.label == 'Regular expression');

      expect(regexp.value, isTrue);
      expect(charsets.value, isFalse, reason: 'выражение по неизвестной кодировке не значит ничего');
    });

    testWidgets('обещаний без действия в окне нет', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      // `First hit` обещал выбор, которого нет: находка у нас — файл, и чтение
      // прекращается на первом совпадении всегда.
      expect(find.text('First hit'), findsNothing);
      for (final flag in tester.widgetList<FcCheckbox>(find.byType(FcCheckbox))) {
        expect(flag.onChanged, isNotNull, reason: 'мёртвый флажок — та же ложь: ${flag.label}');
      }
    });

    testWidgets('размер отбирает находки', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);

      await tester.enterText(fieldWithHint('500k'), '1k');
      await tester.pumpAndSettle();
      await search(tester, '*.dart');

      // Все файлы стенда по байту — под условие не подходит ни один.
      expect(find.text('main.dart'), findsNothing);
    });
  });

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
    // Список окна — тот же, что у панели: находка видна и там, и там.
    expect(find.text('util.dart'), findsWidgets);
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

    expect(app.left.source.scheme, SourceInfo.searchScheme);

    // Деревом, а не кучей: видно, где что нашлось. Вид просит сам источник, и
    // раскрыто оно сразу — иначе находки прятались бы за нажатиями
    // (`docs/spec/file-search.md`, §4).
    expect(app.left.view, TreeView.viewId);
    expect(
      [for (final entry in app.left.entries) '${'  ' * entry.level}${entry.name}'],
      // В порядке обхода, а не по алфавиту: список растёт по ходу поиска, и
      // сортировка вставляла бы новое в середину (`docs/spec/file-search.md`, §4).
      ['Find *.dart', '  main.dart', '  lib', '    main.dart', '    src', '      util.dart'],
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
    for (var i = 0; i < 40 && state.foundCount < 3; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(state.foundCount, greaterThan(0), reason: 'что-то уже нашлось');
    expect(state.busy, isTrue, reason: 'стенд ни о чём, если обход уже кончился');

    // Не нажатием: `pumpAndSettle` внутри него дождался бы конца обхода, а
    // проверяем мы то, что происходит, **пока он идёт**.
    await state.toPanel();
    await tester.pump();

    expect(app.left.source.scheme, SourceInfo.searchScheme, reason: 'находки уже в панели');
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

  testWidgets('«To panel» из правой панели дважды: левая остаётся своей', (tester) async {
    // Живой дефект: поиск из правой панели, «To panel», окно вернули из фона и
    // нажали ещё раз — находки вставали **ещё и в левую** панель.
    final slow = _SlowProvider([
      FakeEntry.directory('/home'),
      for (var i = 0; i < 30; i++) ...[
        FakeEntry.directory('/home/d$i'),
        FakeEntry.file('/home/d$i/found.dart', size: 1),
      ],
    ])..home = '/home';
    app = (await testApp(provider: slow, modules: featureModules())).app;

    await pumpApp(tester);
    app.activate(app.right);
    await tester.pumpAndSettle();

    await openWindow(tester);
    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
    for (var i = 0; i < 40 && state.foundCount < 3; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(state.busy, isTrue, reason: 'стенд ни о чём, если обход уже кончился');

    await state.toPanel();
    await tester.pump();

    expect(app.right.source.scheme, SourceInfo.searchScheme, reason: 'находки в той панели, откуда искали');
    expect(app.left.source.scheme, isNot(SourceInfo.searchScheme), reason: 'левую панель не трогали');

    // Окно вернули из фона и нажали ещё раз: показать ту же вкладку там же.
    await state.toPanel();
    await tester.pump();

    expect(app.right.source.scheme, SourceInfo.searchScheme);
    expect(app.left.source.scheme, isNot(SourceInfo.searchScheme), reason: 'и второе нажатие её не занимает');

    // Дать обходу кончиться: незаконченный оставляет за собой отложенную
    // перерисовку, а висящий таймер роняет виджет-тест.
    for (var i = 0; i < 40 && state.busy; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 120));
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
      ['Find *.dart', '  main.dart', '  lib', '    main.dart', '    src', '      util.dart'],
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

    // Из корня проекции «..» не выводит: выйти можно только явно (§4.6).
    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.source.scheme, SourceInfo.searchScheme, reason: 'случайно из находок не вываливаются');

    await app.left.openPath('/home');
    await tester.pumpAndSettle();

    // Не в корень диска: дерево строится от корня источника, и уход из находок
    // приводил панель туда — курсор оставался на первой строке.
    expect(app.left.source.scheme, isNot(SourceInfo.searchScheme));
    expect(app.left.currentPath, '/home');
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
    await app.left.openPath('/home');
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

    await app.left.openPath('/home');
    await tester.pumpAndSettle();

    expect(app.left.source.scheme, isNot(SourceInfo.searchScheme));
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
    expect(state.foundCount, 2);
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

  testWidgets('плоские виды показывают уровень, не выпадая из находок', (tester) async {
    // Живой дефект, трижды: сперва переход к списку уводил панель в каталог
    // **файла**, потом — внутрь ветви, потом список разворачивался в общую
    // кучу. Источник — фильтр: те же места, только отобранное
    // (`docs/spec/file-search.md`, §4а).
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    app.left.setCursorToName('util.dart');
    await tester.pumpAndSettle();

    await app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();

    // Уровень, где панель стоит: ветви каталогами, находки файлами. Смена вида
    // панель никуда не увела.
    expect(app.left.source.scheme, SourceInfo.searchScheme);
    expect(app.left.entries.map((entry) => entry.name), ['main.dart', 'lib']);
    expect(app.left.entries.map((entry) => entry.level), everyElement(0), reason: 'список, а не лесенка');

    // Краткий вид — то же самое: набор строк тот же, меняется только показ.
    await app.left.setView(BriefView.viewId);
    await tester.pumpAndSettle();
    expect(app.left.entries.map((entry) => entry.name), ['main.dart', 'lib']);

    // В ветвь входят, как в каталог, — и видят отобранное в ней.
    app.left.setCursorToName('lib');
    await app.left.enterCurrent();
    await tester.pumpAndSettle();
    expect(app.left.source.scheme, SourceInfo.searchScheme);
    expect(app.left.entries.map((entry) => entry.name), ['..', 'main.dart', 'src']);

    // «..» ведёт наверх по проекции, а в её корне его нет вовсе: выйти из
    // отобранного можно только явно (§4.6).
    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.entries.map((entry) => entry.name), ['main.dart', 'lib']);

    await app.left.goUp();
    await tester.pumpAndSettle();
    expect(app.left.source.scheme, SourceInfo.searchScheme, reason: 'из корня никуда не вывело');
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

  testWidgets('Enter на ветви сворачивает её, а панель остаётся в находках', (tester) async {
    // Ветвь — показ, а не место: стоять в ней человек не просил, и `Enter`
    // здесь про раскрытие (`docs/spec/file-search.md`, §4а, Н2).
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    app.left.setCursorToName('lib');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(app.left.source.scheme, SourceInfo.searchScheme);
    expect(app.left.entries.map((entry) => entry.name), [
      'Find *.dart',
      'main.dart',
      'lib',
    ], reason: 'ветвь свернулась');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(app.left.entries.map((entry) => entry.name), contains('util.dart'), reason: 'и раскрылась обратно');
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

  testWidgets('из корня находок «..» никуда не выводит', (tester) async {
    // Выйти из отобранного можно только явно — сменой вкладки или переходом по
    // адресу: иначе из списка вываливались одним лишним нажатием (§4.6).
    await pumpApp(tester);
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    expect(app.left.entries.map((entry) => entry.name), isNot(contains('..')));
    await app.left.goUp();
    await tester.pumpAndSettle();

    expect(app.left.source.scheme, SourceInfo.searchScheme);
  });

  testWidgets('«Go to file» ведёт панель в каталог находки и ставит на неё курсор', (tester) async {
    await pumpApp(tester);
    await openWindow(tester);
    // Маска не 'util.dart': набранное стоит в поле, и `find.text` нашёл бы
    // сразу два.
    await search(tester, '*.dart');

    // Щелчок выбирает, ведёт — кнопка: так же, как в `mc`, где по списку
    // ходят, а `Chdir` нажимают.
    // В окне и в панели строка одна и та же — щёлкаем по той, что в окне.
    await tester.tap(find.descendant(of: find.byType(FindFilesResults), matching: find.text('util.dart')));
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

    final window = tester.getRect(find.byType(FindFilesResults));
    expect(find.text('util.dart'), findsWidgets);

    // Ещё один поиск в том же окне: находок другое число, размеры те же.
    await press(tester, 'Again');
    await search(tester, '*.md');

    expect(tester.getRect(find.byType(FindFilesResults)), window, reason: 'окно не поехало');
  });

  testWidgets('растянутое окно отдаёт прибавку списку, а сводка и кнопки остаются внизу', (tester) async {
    // Ради этого список и тянут: видно больше находок разом
    // (`docs/spec/dialog-body.md`).
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');

    final window = tester.getRect(find.byType(FindFilesResults));
    final table = tester.getRect(find.descendant(of: find.byType(FindFilesResults), matching: find.byType(TreeView)));

    // Тянем окно за нижний край — там же, где его тянет человек.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final from = Offset(window.center.dx, window.bottom - 2);
    await mouse.addPointer(location: from);
    await tester.pump();
    await mouse.down(from);
    await tester.pump(const Duration(milliseconds: 20));
    for (var step = 1; step <= 5; step++) {
      await mouse.moveTo(from + Offset(0, 20.0 * step));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();

    final grown = tester.getRect(find.descendant(of: find.byType(FindFilesResults), matching: find.byType(TreeView)));
    expect(grown.height, greaterThan(table.height + 50), reason: 'список не вырос');
    // Сводка под списком и ряд кнопок никуда не делись.
    expect(find.textContaining('Found:'), findsOneWidget);
    expect(
      tester.getRect(find.widgetWithText(FcButton, 'To panel')).bottom,
      greaterThan(grown.bottom),
      reason: 'кнопки должны остаться под списком',
    );
  });

  testWidgets('стрелки в окне водят курсор того же списка, что и в панели', (tester) async {
    // Курсор один на список: окно и панель смотрят в один источник, и второго
    // курсора у него быть не может (`docs/spec/file-search.md`, §4.3).
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
    final session = state.results!;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final first = session.currentEntry?.name;
    expect(first, isNotNull, reason: 'курсор пошёл по списку');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(session.currentEntry?.name, isNot(first), reason: 'и дошёл до следующей строки');
  });

  testWidgets('удержание стрелки в окне повторяет шаг', (tester) async {
    // Живой дефект: в окне находок удержание стрелки не двигало курсор вовсе —
    // окно принимало только нажатие, а автоповтор приходит своим событием.
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
    final session = state.results!;
    final start = session.cursorIndex;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(session.cursorIndex, start + 3, reason: 'три события — три шага');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(session.cursorIndex, start + 1, reason: 'и вверх тоже');
  });

  testWidgets('удержание PageDown в окне листает дальше первой страницы', (tester) async {
    final many = <FakeEntry>[FakeEntry.directory('/big')];
    for (var i = 0; i < 200; i++) {
      many.add(FakeEntry.file('/big/file$i.dart', size: 1));
    }
    app =
        (await testApp(
          provider: InMemoryTreeProvider(many),
          modules: featureModules(),
          settings: AppSettings(left: PanelSettings.defaults('/big'), right: PanelSettings.defaults('/big')),
        )).app;

    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');

    final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
    final session = state.results!;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    final page = session.cursorIndex;
    expect(page, greaterThan(0), reason: 'первая страница пролистана');

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);

    expect(session.cursorIndex, greaterThan(page), reason: 'удержание листает дальше');
  });

  testWidgets('тысяча находок — строк собрано столько, сколько видно', (tester) async {
    // Общий список окон собирает все строки разом, и на тысячах находок
    // приложение вставало намертво. Панельный список ленив — им окно и
    // рисует находки (`docs/spec/file-search.md`, §3.2).
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
    expect(state.foundCount, 1000, reason: 'нашлось всё');
    expect(find.text('Found: 1000'), findsOneWidget);

    // А построено — по числу видимых строк, а не по числу находок: список в
    // окне тот же, что в панели, и ленивость у него оттуда же.
    final built =
        tester.widgetList(find.descendant(of: find.byType(FindFilesResults), matching: find.byType(Row))).length;
    expect(built, lessThan(60), reason: 'список ленивый: строк собрано столько, сколько влезло в обзор');
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

    expect(state.foundCount, 300);
    expect(redraws, lessThan(50), reason: 'сообщений о находках 300, а перерисовок — единицы');
  });

  group('вкладка поиска', () {
    testWidgets('окно и панель показывают один список', (tester) async {
      await pumpApp(tester, size: const Size(1200, 800));
      await openWindow(tester);
      await search(tester, '*.dart');

      final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
      expect(state.results, isNotNull);
      // Вкладка завелась, но панель человек не отдавал: она показывает прежнее.
      expect(identical(state.results, app.left), isFalse, reason: 'панель не тронута');
      expect(app.left.source.scheme, isNot(SourceInfo.searchScheme));

      final was = state.results!.entries.length;
      await press(tester, 'To panel');

      // А теперь показывает ту же сессию: передавать список некуда, он один.
      expect(identical(state.results, app.left), isTrue, reason: '«To panel» ничего не перекладывает');
      expect(app.left.entries.length, was, reason: 'и ничего не перечитывает');
    });

    testWidgets('два поиска — две вкладки и два разных списка', (tester) async {
      // Личность источника — его адрес: у разных запросов он разный, и делить
      // один список им нельзя (`docs/spec/file-search.md`, §4.1).
      await pumpApp(tester);
      await openWindow(tester);
      await search(tester, '*.dart');
      final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
      final first = state.results!;
      // Кнопка «Background» жива только у идущего обхода, а на подставном
      // дереве он кончается мгновенно.
      state.toBackground();
      await tester.pumpAndSettle();

      await openWindow(tester);
      await search(tester, '*.md');
      final second = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state.results!;

      expect(identical(first, second), isFalse, reason: 'вкладки разные');
      expect(first.entries.map((entry) => entry.name), contains('main.dart'));
      expect(second.entries.map((entry) => entry.name), contains('readme.md'));
      expect(second.entries.map((entry) => entry.name), isNot(contains('main.dart')));
    });

    testWidgets('заголовок панели — имя списка, а не каталог поиска', (tester) async {
      await pumpApp(tester);
      await openWindow(tester);
      await search(tester, '*.dart');
      await press(tester, 'To panel');

      // Имя списка, а не каталог, в котором искали: панель спрашивает его у
      // источника, и уходит оно вместе с ним.
      expect(app.left.headerText, 'Find *.dart');

      await app.left.openPath('/home');
      await tester.pumpAndSettle();
      expect(app.left.headerText, isNull, reason: 'ушли из находок — имя пропало само');
    });

    testWidgets('«Close» уносит вкладку вместе с окном', (tester) async {
      await pumpApp(tester);
      final tabs = app.panels.length;
      await openWindow(tester);
      await search(tester, '*.dart');
      expect(app.panels.length, tabs + 1, reason: 'вкладка завелась');

      await press(tester, 'Close');

      expect(app.panels.length, tabs, reason: 'и ушла вместе с окном');
      expect(app.left.source.scheme, isNot(SourceInfo.searchScheme));
    });

    testWidgets('поиск только по содержимому не ломает адреса', (tester) async {
      // Тот самый запрос, на котором прежняя сборка разваливалась: имя пустое,
      // и оно было звеном пути (§4.7).
      final files = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/lib'),
        FakeEntry.file('/home/lib/found.dart', content: utf8.encode('// TODO\n')),
        FakeEntry.file('/home/clean.dart', content: utf8.encode('всё сделано\n')),
      ])..home = '/home';
      final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: files, modules: featureModules(), settings: settings)).app;

      await pumpApp(tester);
      await openWindow(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(FindFilesForm),
          matching: find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'TODO'),
        ),
        'TODO',
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await press(tester, 'To panel');

      expect(app.left.headerText, 'Find "TODO"', reason: 'имя списка не бывает пустым');
      expect(app.left.entries.map((entry) => entry.name), contains('lib'));
      for (final entry in app.left.entries) {
        expect(entry.path, isNot(contains('//')), reason: 'в адресах строк нет двойного слэша');
      }

      await app.left.openPath('/home');
      await tester.pumpAndSettle();
      expect(app.left.currentPath, '/home', reason: 'выход из находок — явный');
    });
  });

  group('пока список растёт', () {
    /// Медленное дерево с байтами: находки прибывают пачками, и между ними
    /// человек успевает нажать клавишу.
    Future<FindFilesState> streaming(WidgetTester tester) async {
      final slow = _SlowContentProvider([
        FakeEntry.directory('/home'),
        for (var i = 0; i < 30; i++) ...[
          FakeEntry.directory('/home/d$i'),
          FakeEntry.file('/home/d$i/found.dart', content: utf8.encode('// файл $i\n')),
        ],
      ])..home = '/home';
      app = (await testApp(provider: slow, modules: featureModules())).app;

      await pumpApp(tester, size: const Size(1200, 800));
      await openWindow(tester);
      await tester.enterText(input, '*.dart');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final state = tester.widget<FindFilesResults>(find.byType(FindFilesResults)).state;
      for (var i = 0; i < 40 && state.foundCount < 4; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(state.busy, isTrue, reason: 'стенд ни о чём, если обход уже кончился');
      // Курсор — на первую находку, а не на последнюю: у последней больше
      // шансов уцелеть случайно.
      state.results!.setCursorToName('found.dart');
      await tester.pump();
      expect(state.canGoTo, isTrue);
      return state;
    }

    testWidgets('«Go to file» над находкой срабатывает с первого раза', (tester) async {
      // Живой дефект: ссылка на строку состояла из места и номера списка, а
      // номер рос двадцать раз в секунду — заявка протухала за 50 мс, и нажатие
      // уходило в никуда (`docs/spec/client-server.md`, §5.5а).
      final state = await streaming(tester);

      await state.goTo();
      state.stop();
      await tester.pumpAndSettle();

      expect(app.left.currentPath, startsWith('/home/d'));
      expect(app.left.currentEntry?.name, 'found.dart');
    });

    testWidgets('строка отзывается, пока список растёт', (tester) async {
      // Корень и `F3`, и `F4`, и `Enter`: все они спрашивают ядро о строке под
      // курсором. Прежде ссылка протухала за 50 мс, и ядро отвечало «нет такой
      // строки» — просмотр молчал, а правка показывала окно «только для
      // чтения» над обычным файлом (`docs/spec/client-server.md`, §5.5а).
      final state = await streaming(tester);
      final session = state.results!;
      final entry = session.currentEntry!;

      // Пачка за пачкой: список успел смениться не раз, а строка та же.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(await session.canWriteTo(entry), isTrue, reason: 'писать в неё можно — и это правда');
      final attributes = await session.readAttributes(entry);
      expect(attributes, isNot(NodeAttributes.unknown), reason: 'строка нашлась, а не потерялась');

      state.stop();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('«Tree with contents» остаётся в находках, а не уезжает на диск', (tester) async {
    // Живой дефект: спутник дерева шёл за «куда пойдёт операция» и уводил
    // столбец в настоящий каталог — а оттуда дерево строится от корня диска.
    // Спутник работает с тем же провайдером, и прозрачность для него та же
    // (`docs/spec/file-search.md`, §4.5).
    await pumpApp(tester, size: const Size(1200, 800));
    await openWindow(tester);
    await search(tester, '*.dart');
    await press(tester, 'To panel');

    await app.left.setView(CombinedView.viewId);
    await tester.pumpAndSettle();

    final tab = app.panelOf(app.left)!;
    expect(tab.sessions, hasLength(2), reason: 'у вида два столбца');
    for (final session in tab.sessions) {
      expect(session.source.scheme, SourceInfo.searchScheme, reason: 'оба столбца — в находках');
    }
    // Дерево показывает проекцию, а не весь диск.
    final tree = tab.sessions.first;
    expect(tree.entries.map((entry) => entry.name), isNot(contains('Users')));
  });

  group('восстановление', () {
    testWidgets('панель, оставленную в находках, поднимают списком', (tester) async {
      // Обход при запуске никто не заводит — уходить в обход диска на старте
      // приложение не должно. Но адрес восстанавливается, и список зовётся
      // по-прежнему (`docs/spec/file-search.md`, §4.6).
      final provider = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/main.dart', size: 1),
      ])..home = '/home';
      final address = SearchAddress(where: '/home', query: const SearchQuery(mask: '*.dart')).toString();
      final settings = AppSettings(left: PanelSettings(path: address), right: PanelSettings.defaults('/home'));
      app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

      await pumpApp(tester);

      expect(app.left.source.scheme, SourceInfo.searchScheme, reason: 'список на месте');
      expect(app.left.headerText, 'Find *.dart', reason: 'и зовётся по запросу');
      expect(app.left.entries.where((entry) => entry.name == 'main.dart'), isEmpty, reason: 'а обход не заводили');

      // Повторить его — дело одного окна: запрос уже в адресе.
      await openWindow(tester);
      expect(tester.widget<TextField>(input).controller!.text, '*.dart');

      // Прогрев оболочки при запуске ставит свой таймер; дожидаемся его, иначе
      // стенд ругается на висящий таймер, и правильно делает.
      await tester.pump(const Duration(seconds: 11));
    });
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
      // Имя работы — у самой работы: на экране им подписаны и полоска, и
      // вкладка, и потому «ровно одно» тут спрашивать не о чем.
      expect(app.operations.at(ViewportPosition.left).single.title, 'Find *.dart', reason: 'полоска называет поиск');
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

      await tester.tap(find.textContaining('Find *.dart').last);
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
      for (var i = 0; i < 40 && state.foundCount == 0; i++) {
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
      final strips = app.operations.at(ViewportPosition.left);
      expect(strips, hasLength(2));
      expect(strips.map((run) => run.title), ['Find *.dart', 'Find *.md']);
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
