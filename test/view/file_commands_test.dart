import 'dart:io';

import 'package:flex_commander/app.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Файловые команды рисуют свои окна сами, поэтому и проверяются целиком:
/// от нажатия клавиши до изменившейся панели.
void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_file_cmd');

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: defaultCommandRegistry(),
      saveDelay: const Duration(milliseconds: 5),
    );
  });

  tearDown(() async {
    app.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Даёт доработать асинхронной части команды: операция, перечитывание панели.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  List<String> namesOf() => app.left.nodes.map((node) => node.name).toList();

  group('создание каталога', () {
    testWidgets('F7 открывает окно команды с полем ввода', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      // Заголовок окна — название самой команды.
      expect(find.text('Mk Dir'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue);
    });

    testWidgets('введённое имя создаёт каталог и закрывает окно', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(find.byType(TextField), 'docs');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await settle(tester);

      expect(find.byType(TextField), findsNothing);
      expect(namesOf(), contains('docs'));
      expect(app.left.currentNode?.name, 'docs');
    });

    testWidgets('Enter в поле подтверждает ввод', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(find.byType(TextField), 'docs');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(namesOf(), contains('docs'));
    });

    testWidgets('отмена ничего не создаёт', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(find.byType(TextField), 'docs');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(find.byType(TextField), findsNothing);
      expect(namesOf(), isNot(contains('docs')));
    });

    testWidgets('ошибка показывается в том же окне, а имя остаётся', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(find.byType(TextField), 'bin');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await settle(tester);

      // Окно не закрылось: имя можно исправить и попробовать снова.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.textContaining('Already exists'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'docs');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await settle(tester);

      expect(namesOf(), contains('docs'));
    });

    testWidgets('кнопка F7 в нижней панели делает то же самое', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Mk Dir'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('удаление', () {
    testWidgets('F8 спрашивает подтверждение и удаляет', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      expect(find.textContaining('Move «notes.txt» to Trash?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      expect(namesOf(), isNot(contains('notes.txt')));
    });

    testWidgets('отказ оставляет объект на месте', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      expect(namesOf(), contains('notes.txt'));
    });

    testWidgets('удаляются все помеченные объекты', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      app.left.toggleCurrentMark();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      expect(find.textContaining('Move 2 items to Trash?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      expect(namesOf(), isNot(contains('notes.txt')));
      expect(namesOf(), isNot(contains('report.xlsx')));
      expect(app.left.selection.isEmpty, isTrue);
    });

    testWidgets('Shift-F8 предупреждает, что удаление безвозвратное', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.text('Delete permanently'), findsWidgets);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
    });

    testWidgets('ошибка предлагает пропустить, пропустить все или отменить', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();
      // Объект исчез уже после того, как панель его показала.
      provider.removeEntry('/home/notes.txt');

      await press(tester, LogicalKeyboardKey.f8);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      expect(find.textContaining('Not found'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Skip all'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Skip'));
      await settle(tester);

      // Ответили — окно закрылось само.
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('на «..» команда недоступна', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToFirst();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);

      expect(find.textContaining('to Trash?'), findsNothing);
    });
  });

  group('окна команд', () {
    testWidgets('пока окно открыто, панели не отвечают на клавиши', (tester) async {
      await pumpApp(tester);
      final cursor = app.left.cursorIndex;

      await press(tester, LogicalKeyboardKey.f7);
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(app.left.cursorIndex, cursor);
    });

    testWidgets('после закрытия окна клавиши снова работают', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.f7);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(app.left.cursorIndex, 1);
    });
  });
}
