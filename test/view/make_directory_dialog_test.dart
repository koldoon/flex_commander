import 'dart:io';

import 'package:flex_commander/app.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flex_commander/view/dialogs/dialog_user_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late DialogUserInteraction dialogs;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_dialog');
    dialogs = DialogUserInteraction();

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      commands: defaultCommandRegistry(),
      dialogs: dialogs,
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

    await tester.pumpWidget(FlexCommanderApp(controller: app, navigatorKey: dialogs.navigatorKey));
    await app.start();
    await tester.pumpAndSettle();
  }

  Future<void> pressF7(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.pumpAndSettle();
  }

  testWidgets('приложение подключает ключ навигатора к диалогам', (tester) async {
    await pumpApp(tester);

    // Без этого диалоги молча не открываются: команда получает «отказ»
    // пользователя и ничего не делает — ровно так ошибка и выглядела.
    expect(dialogs.navigatorKey.currentContext, isNotNull);
    expect(dialogs.navigatorKey.currentState, isNotNull);
  });

  testWidgets('F7 открывает диалог с полем ввода', (tester) async {
    await pumpApp(tester);
    await pressF7(tester);

    expect(find.text('Create directory'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // Поле сразу готово к вводу: имя набирается без лишнего клика.
    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue);
  });

  testWidgets('введённое имя создаёт каталог', (tester) async {
    await pumpApp(tester);
    await pressF7(tester);

    await tester.enterText(find.byType(TextField), 'docs');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(TextField), findsNothing);
    expect(app.left.nodes.map((n) => n.name), contains('docs'));
    expect(app.left.currentNode?.name, 'docs');
  });

  testWidgets('Enter в поле подтверждает ввод', (tester) async {
    await pumpApp(tester);
    await pressF7(tester);

    await tester.enterText(find.byType(TextField), 'docs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    expect(app.left.nodes.map((n) => n.name), contains('docs'));
  });

  testWidgets('отмена ничего не создаёт', (tester) async {
    await pumpApp(tester);
    await pressF7(tester);

    await tester.enterText(find.byType(TextField), 'docs');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(app.left.nodes.map((n) => n.name), isNot(contains('docs')));
  });

  testWidgets('существующее имя показывает ошибку', (tester) async {
    await pumpApp(tester);
    await pressF7(tester);

    await tester.enterText(find.byType(TextField), 'bin');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot create directory'), findsOneWidget);
    expect(find.textContaining('Already exists'), findsOneWidget);
  });

  testWidgets('кнопка F7 в нижней панели делает то же самое', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Mk Dir'));
    await tester.pumpAndSettle();

    expect(find.text('Create directory'), findsOneWidget);
  });

  group('удаление', () {
    testWidgets('спрашивает подтверждение и удаляет', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Move «notes.txt» to Trash?'), findsOneWidget);

      // В диалоге кнопка подтверждения называется так же, как команда.
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      // Удаление асинхронное: подтверждение, операция, перечитывание панели.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(app.left.nodes.map((n) => n.name), isNot(contains('notes.txt')));
    });

    testWidgets('отказ оставляет объект на месте', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(app.left.nodes.map((n) => n.name), contains('notes.txt'));
    });

    testWidgets('ошибка предлагает пропустить, пропустить все или отменить', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();
      // Объект исчез уже после того, как панель его показала.
      provider.removeEntry('/home/notes.txt');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot delete'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Skip all'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Cannot delete'), findsNothing);
    });
  });
}
