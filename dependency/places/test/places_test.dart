import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_places/fc_places.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/dnd/system_drag_and_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Боковая полоса избранного (`docs/spec/favorites-sidebar.md`, §11).
void main() {
  group('адрес места', () {
    test('внутри домашнего каталога хранится через ~', () {
      expect(PlaceAddress.normalize('/home/me/Downloads', home: '/home/me'), '~/Downloads');
      expect(PlaceAddress.normalize('/home/me', home: '/home/me'), '~');
      expect(PlaceAddress.normalize('/home/meow', home: '/home/me'), '/home/meow', reason: 'общий префикс — не дом');
      expect(PlaceAddress.normalize('/work/', home: '/home/me'), '/work', reason: 'хвостовой разделитель не отличие');
      expect(PlaceAddress.normalize('/'), '/');
    });

    test('род места — по адресу', () {
      expect(PlaceAddress.kindOf('~'), PlaceKind.home);
      expect(PlaceAddress.kindOf('~/Downloads'), PlaceKind.downloads);
      expect(PlaceAddress.kindOf('/Applications'), PlaceKind.applications);
      expect(PlaceAddress.kindOf('/'), PlaceKind.volume);
      expect(PlaceAddress.kindOf('/Volumes/Backup'), PlaceKind.volume);
      expect(PlaceAddress.kindOf('/Volumes/Backup/photos'), PlaceKind.folder);
      expect(PlaceAddress.kindOf('ssh://shark/home'), PlaceKind.server);
      expect(PlaceAddress.kindOf('/home/a.zip'), PlaceKind.archive);
      expect(PlaceAddress.kindOf('/home/a.zip/inner'), PlaceKind.archive);
      expect(PlaceAddress.kindOf('/home/zipper'), PlaceKind.folder);
    });

    test('имя по умолчанию — последнее звено, у знакомых — ключ перевода', () {
      expect(PlaceAddress.defaultName('/work/projects'), 'projects');
      expect(PlaceAddress.defaultName('~'), 'Home');
      expect(PlaceAddress.defaultName('/'), 'Root');
      expect(PlaceAddress.defaultName('ssh://shark/home'), 'home');
      expect(PlaceAddress.isTranslatedName('~/Desktop'), isTrue);
      expect(PlaceAddress.isTranslatedName('/work/Desktop'), isFalse, reason: 'чужой Desktop — просто каталог');
    });
  });

  group('настройки полосы', () {
    test('нет своего списка — места по умолчанию; пустой свой — пустой', () {
      final fresh = PlacesSettings()..fromMap({});
      expect(fresh.places.map((place) => place.address), [
        '~',
        '~/Desktop',
        '~/Documents',
        '~/Downloads',
        '/Applications',
        '/',
      ]);

      final empty = PlacesSettings()..fromMap({'places': <Object>[]});
      expect(empty.places, isEmpty, reason: 'убрал всё — значит хочет пустую полосу');
    });

    test('круг сохранения: адрес, имя, показ, ширина', () {
      final settings =
          PlacesSettings()
            ..places = [Place(address: '/work', name: 'Work'), Place(address: '~')]
            ..visible = false
            ..width = 180;
      final map = <String, dynamic>{};
      settings.toMap(map);

      final back = PlacesSettings()..fromMap(map);
      expect(back.places.map((place) => (place.address, place.name)), [('/work', 'Work'), ('~', null)]);
      expect(back.visible, isFalse);
      expect(back.width, 180);
    });
  });

  group('полоса в окне', () {
    late AppRuntime runtime;
    late InMemoryTreeProvider provider;

    Application app() => runtime.app;

    setUp(() async {
      // Под `flutter test` полоса по умолчанию скрыта — здесь она нужна.
      PlacesSettings.visibleByDefault = true;
      addTearDown(() => PlacesSettings.visibleByDefault = false);
      provider = InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/Desktop'),
        FakeEntry.file('/home/Desktop/note.txt', size: 4),
        FakeEntry.directory('/home/Documents'),
        FakeEntry.directory('/Applications'),
        FakeEntry.directory('/work'),
        FakeEntry.directory('/work/inner'),
        FakeEntry.file('/work/a.txt', size: 4),
      ])..home = '/home';
      runtime = await testApp(
        provider: provider,
        modules: featureModules(),
        settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/work')),
        toastDuration: const Duration(milliseconds: 1),
      );
      await runtime.app.start();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await tester.pumpAndSettle();
    }

    PlacesState places() => app().view.contentAt(ViewportPosition.sidebar)! as PlacesState;

    Finder row(String name) => find.descendant(of: find.byType(PlacesView), matching: find.text(name));

    // На прогоне платформа не macOS, и `Cmd` в привязке читается как `Ctrl`
    // (`KeyCombination.parse`): `Cmd-Enter` здесь — это `Ctrl-Enter`.
    const cmd = [LogicalKeyboardKey.controlLeft];

    // Клавиши `Ctrl-Cmd-…` закреплены только на macOS: вне его `Cmd`
    // разбирается как `Ctrl`, и `Ctrl-Cmd-T` свёлся бы к `Cmd-T` командной
    // строки. Прогон идёт не на macOS — эти команды вызываются по имени, а их
    // клавиши проверяет отдельный тест с платформой macOS (внизу).
    Future<void> run(WidgetTester tester, String command) async {
      app().commands.run(command);
      await tester.pumpAndSettle();
    }

    Future<void> key(WidgetTester tester, LogicalKeyboardKey key, {List<LogicalKeyboardKey> held = const []}) async {
      for (final modifier in held) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(key);
      for (final modifier in held.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('полоса стоит слева, места по умолчанию названы', (tester) async {
      await pumpApp(tester);
      expect(find.byType(PlacesView), findsOneWidget);
      expect(find.byWidgetPredicate((widget) => widget is FcPathPlate && widget.path == 'Favorites'), findsOneWidget);
      for (final name in ['Home', 'Desktop', 'Documents', 'Downloads', 'Applications', 'Root']) {
        expect(row(name), findsOneWidget, reason: 'нет места $name');
      }
      final sidebar = tester.getRect(find.byType(PlacesView));
      final command = tester.getRect(find.byType(FcPanelFrame).at(1));
      expect(sidebar.right, lessThan(command.left), reason: 'полоса левее панелей');
    });

    testWidgets('щелчок — в активную панель, Cmd-щелчок — в соседнюю, активная та же', (tester) async {
      await pumpApp(tester);

      await tester.tap(row('Desktop'));
      await tester.pumpAndSettle();
      expect(app().left.currentPath, '/home/Desktop');
      expect(app().activePanel, same(app().left));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(row('Documents'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(app().right.currentPath, '/home/Documents');
      expect(app().left.currentPath, '/home/Desktop', reason: 'активная не тронута');
      expect(app().activePanel, same(app().left), reason: 'соседняя активной не становится');
    });

    FcPathPlate plate(WidgetTester tester) => tester.widget<FcPathPlate>(
      find.byWidgetPredicate((widget) => widget is FcPathPlate && widget.path == 'Favorites'),
    );

    testWidgets('нажатие сразу ставит курсор и зажигает плашку; отпустили — переход, ввод панели', (tester) async {
      await pumpApp(tester);
      expect(plate(tester).active, isFalse, reason: 'пока ввод у панели, плашка погашена');

      final gesture = await tester.startGesture(tester.getCenter(row('Documents')));
      await tester.pump();
      expect(places().cursor, 2, reason: 'курсор — по нажатию, а не по отпусканию');
      expect(app().view.activeArea, ViewportPosition.sidebar);
      expect(plate(tester).active, isTrue);
      expect(app().left.currentPath, '/home', reason: 'перехода до отпускания нет');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(app().left.currentPath, '/home/Documents');
      expect(app().view.activeArea, ViewportPosition.left, reason: 'дошли — ввод панели');
      expect(plate(tester).active, isFalse);
    });

    testWidgets('ввод у полосы — плашка Favorites горит', (tester) async {
      await pumpApp(tester);
      await run(tester, FocusPlacesCommand.commandId);
      expect(plate(tester).active, isTrue);
      await key(tester, LogicalKeyboardKey.escape);
      expect(plate(tester).active, isFalse);
    });

    testWidgets('не дошли — тост и приглушение; дошли — приглушение снято', (tester) async {
      await pumpApp(tester);

      await tester.tap(row('Downloads'));
      await tester.pumpAndSettle();
      final downloads = places().places.firstWhere((place) => place.address == '~/Downloads');
      expect(places().isUnreachable(downloads), isTrue);
      expect(find.ancestor(of: row('Downloads'), matching: find.byType(Opacity)), findsOneWidget);
      expect(app().left.currentPath, '/home', reason: 'панель осталась на месте');

      provider.add(FakeEntry.directory('/home/Downloads'));
      await tester.tap(row('Downloads'));
      await tester.pumpAndSettle();
      expect(places().isUnreachable(downloads), isFalse);
      expect(app().left.currentPath, '/home/Downloads');
    });

    testWidgets('клавиатура: фокус в полосу, ход, Enter, Cmd-Enter, Esc', (tester) async {
      await pumpApp(tester);

      await run(tester, FocusPlacesCommand.commandId);
      expect(app().view.activeArea, ViewportPosition.sidebar);

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(places().cursor, 1);
      await key(tester, LogicalKeyboardKey.enter);
      expect(app().left.currentPath, '/home/Desktop');
      expect(app().view.activeArea, ViewportPosition.left, reason: 'после перехода ввод у панели');

      await run(tester, FocusPlacesCommand.commandId);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.enter, held: cmd);
      expect(app().right.currentPath, '/home/Documents');
      expect(app().view.activeArea, ViewportPosition.sidebar, reason: 'переход в соседнюю ввода не уводит');

      await key(tester, LogicalKeyboardKey.escape);
      expect(app().view.activeArea, ViewportPosition.left);
    });

    testWidgets('пока ввод в полосе, клавиши панели молчат', (tester) async {
      await pumpApp(tester);
      final before = app().left.currentEntry?.name;

      await run(tester, FocusPlacesCommand.commandId);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(app().left.currentEntry?.name, before, reason: 'стрелка ушла полосе, а не панели');
    });

    testWidgets('F2 — имя на месте подписи: Enter принимает, Esc отменяет', (tester) async {
      await pumpApp(tester);

      await run(tester, FocusPlacesCommand.commandId);
      await key(tester, LogicalKeyboardKey.f2);
      expect(find.descendant(of: find.byType(PlacesView), matching: find.byType(TextField)), findsOneWidget);

      final field = find.descendant(of: find.byType(PlacesView), matching: find.byType(TextField));
      await tester.enterText(field, 'Дом');
      // `Enter` в поле приходит от системы действием ввода, а не клавишей.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(row('Дом'), findsOneWidget);
      expect(places().places.first.name, 'Дом');
      expect(app().view.activeArea, ViewportPosition.sidebar, reason: 'Enter принял имя, а не ушёл к месту');

      await key(tester, LogicalKeyboardKey.f2);
      await tester.enterText(field, 'Не то');
      await key(tester, LogicalKeyboardKey.escape);
      expect(row('Дом'), findsOneWidget, reason: 'Esc вернул прежнее имя');
      expect(app().view.activeArea, ViewportPosition.sidebar, reason: 'Esc отменил правку, а не увёл ввод');

      await key(tester, LogicalKeyboardKey.f2);
      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(row('Home'), findsOneWidget, reason: 'пустое имя — имя по умолчанию');
      expect(places().places.first.name, isNull);
    });

    testWidgets('Del убирает место, кнопка в настройках возвращает все', (tester) async {
      await pumpApp(tester);

      await run(tester, FocusPlacesCommand.commandId);
      await key(tester, LogicalKeyboardKey.delete);
      expect(row('Home'), findsNothing);
      expect(places().places, hasLength(5));

      places().restoreDefaults();
      await tester.pumpAndSettle();
      expect(row('Home'), findsOneWidget);
      expect(places().places, hasLength(6));
    });

    testWidgets('Ctrl-Cmd-T кладёт текущий каталог; повтор не заводится', (tester) async {
      await pumpApp(tester);
      app().activate(app().right);
      await tester.pumpAndSettle();

      await run(tester, AddPlaceCommand.commandId);
      expect(places().places.last.address, '/work');
      expect(row('work'), findsOneWidget);

      await run(tester, AddPlaceCommand.commandId);
      expect(places().places.where((place) => place.address == '/work'), hasLength(1));

      // Домашний каталог целиком и `~` — одно место.
      app().activate(app().left);
      await tester.pumpAndSettle();
      await run(tester, AddPlaceCommand.commandId);
      expect(places().places.where((place) => place.address == '/home'), isEmpty);
      expect(places().cursor, 0, reason: 'курсор встал на имеющееся место');
    });

    testWidgets('Ctrl-Cmd-S прячет и показывает; выбор помнится', (tester) async {
      await pumpApp(tester);
      final settings = app().moduleSettings(Places.moduleId).section(PlacesSettings.new);

      await run(tester, TogglePlacesCommand.commandId);
      expect(find.byType(PlacesView), findsNothing);
      expect(settings.visible, isFalse);

      await run(tester, TogglePlacesCommand.commandId);
      expect(find.byType(PlacesView), findsOneWidget);
      expect(settings.visible, isTrue);
    });

    testWidgets('окно над панелью встаёт над панелью и с полосой', (tester) async {
      await pumpApp(tester);
      final left = app().view.panelArea(ViewportPosition.left);
      final right = app().view.panelArea(ViewportPosition.right);
      final sidebar = tester.getRect(find.byType(PlacesView));
      const window = 1000.0;

      expect(left.start, greaterThan(sidebar.right / window - 0.01), reason: 'левая панель правее полосы');
      expect(left.end, closeTo(right.start, 1e-9));
      expect(right.end, 1);

      final panel = tester.getRect(find.byType(FcPanelFrame).at(1));
      expect(left.center * window, closeTo(panel.center.dx, 4), reason: 'середина области — середина левой панели');
    });

    testWidgets('перестановка мышью', (tester) async {
      await pumpApp(tester);
      final metrics = FcTheme.of(tester.element(find.byType(PlacesView))).metrics;

      await tester.drag(row('Home'), Offset(0, metrics.rowHeight * 2 + 2));
      await tester.pumpAndSettle();
      expect(places().places.map((place) => place.address).take(3), ['~/Desktop', '~/Documents', '~']);
    });

    testWidgets('бросок каталога из Finder — место в точке вставки, файл — тост', (tester) async {
      await pumpApp(tester);
      final temp = Directory.systemTemp.createTempSync('places');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/note.txt')..writeAsStringSync('x');

      final metrics = FcTheme.of(tester.element(find.byType(PlacesView))).metrics;
      final first = tester.getRect(row('Home'));
      final at = Offset(first.center.dx, first.top + metrics.rowHeight);

      Future<void> drop(List<String> paths) async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          SystemDropService.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('drop', {'x': at.dx, 'y': at.dy, 'paths': paths, 'move': false}),
          ),
          (_) {},
        );
        // Без досыпания: тост живёт миг, а проверить его надо.
        await tester.pump();
      }

      await drop([temp.path]);
      await tester.pumpAndSettle();
      expect(places().places[1].address, temp.path, reason: 'встало между первым и вторым');
      expect(app().view.dialogs, isEmpty, reason: 'на полосу ничего не копируется — окна работы нет');

      await drop([file.path]);
      expect(places().places.where((place) => place.address == file.path), isEmpty);
      expect(find.text('Only directories go to the sidebar'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('клавиши на macOS', () {
    late AppRuntime runtime;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      runtime = await testApp(
        provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
        modules: featureModules(),
      );
    });

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('как в Finder: Ctrl-Cmd-S, Ctrl-Cmd-T; и Ctrl-Cmd-Left — в полосу', () {
      final commands = runtime.commands;
      expect(commands.bindingsOf(TogglePlacesCommand.commandId).map((binding) => '${binding.keys}'), ['Ctrl-Cmd-S']);
      expect(commands.bindingsOf(AddPlaceCommand.commandId).map((binding) => '${binding.keys}'), ['Ctrl-Cmd-T']);
      expect(commands.bindingsOf(FocusPlacesCommand.commandId).map((binding) => '${binding.keys}'), ['Ctrl-Cmd-Left']);
    });
  });
}
