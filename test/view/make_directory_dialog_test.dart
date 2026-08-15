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
}
