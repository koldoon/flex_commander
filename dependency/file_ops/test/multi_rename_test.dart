import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно группового переименования и то, что из него выходит
/// (`docs/spec/multi-rename.md`).
void main() {
  late InMemoryTreeProvider provider;
  late AppRuntime runtime;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/IMG_0041.JPG', size: 1),
      FakeEntry.file('/home/IMG_0042.JPG', size: 1),
      FakeEntry.file('/home/notes.txt', size: 1),
    ])..home = '/home';

    runtime = await testApp(
      provider: provider,
      modules: [const Navigation(), const FileOps()],
      backend: [const FileOps()],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
  });

  /// Кадрами с шагом, а не `pumpAndSettle`: курсор в поле моргает по таймеру,
  /// и ждать тишины бесполезно.
  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var step = 0; step < frames; step++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Рисует окно команды так же, как его рисует ядро: рама снаружи.
  Future<AppCommand> pumpDialog(WidgetTester tester) async {
    final command = runtime.commands.create(MultiRenameCommand.commandId)!;
    await command.executeWith();
    await settle(tester);
    final spec = runtime.app.view.dialogs.single;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: Center(child: SizedBox(width: 700, height: 500, child: spec.content))),
      ),
    );
    await settle(tester);
    return command;
  }

  /// Поле маски имени — по его же подсказке: подписи в форме живут отдельным
  /// столбцом, и предка у поля с ними нет.
  Finder nameField() => find.byWidgetPredicate((widget) => widget is FcTextField && widget.hintText == '[N]');

  /// Пометка ставится и доезжает до ядра кадрами: в виджетном прогоне часы
  /// поддельные, и ждать очередь событий бесполезно.
  Future<void> markPhotos(WidgetTester tester) async {
    runtime.app.left.setMarks({'/home/IMG_0041.JPG', '/home/IMG_0042.JPG'}, by: MarkChange.person);
    await settle(tester);
  }

  testWidgets('без целей команда невыполнима', (tester) async {
    final command = runtime.commands.create(MultiRenameCommand.commandId)!;
    runtime.app.left.setCursorToName('..');
    await settle(tester);

    expect(runtime.commands.isExecutable(command), isFalse);
  });

  testWidgets('предпросмотр показывает обе колонки', (tester) async {
    await markPhotos(tester);
    await pumpDialog(tester);

    expect(find.text('Was'), findsOneWidget);
    expect(find.text('Becomes'), findsOneWidget);
    expect(find.text('IMG_0041.JPG'), findsWidgets, reason: 'левая колонка — как есть');
  });

  testWidgets('набранная маска сразу видна в правой колонке', (tester) async {
    await markPhotos(tester);
    await pumpDialog(tester);

    await tester.enterText(nameField(), 'Отпуск_[C]');
    await settle(tester);

    expect(find.text('Отпуск_1.JPG'), findsOneWidget);
    expect(find.text('Отпуск_2.JPG'), findsOneWidget, reason: 'счётчик нумерует в порядке списка');
  });

  testWidgets('негодная маска объясняется прямо по ходу набора', (tester) async {
    await markPhotos(tester);
    await pumpDialog(tester);

    await tester.enterText(nameField(), '[N2-5');
    await settle(tester);

    expect(find.byType(FcErrorText), findsOneWidget);
  });

  testWidgets('переименование доходит до диска тем, что показал предпросмотр', (tester) async {
    await markPhotos(tester);
    final command = await pumpDialog(tester);

    await tester.enterText(nameField(), 'Отпуск_[C]');
    await settle(tester);
    await tester.tap(find.widgetWithText(FcButton, 'Rename'));
    await settle(tester);
    await settle(tester);

    final home = (await provider.resolvePath().run('/home'))! as DirectoryNode;
    final names = [for (final node in await provider.listChildren(home)) node.name]..sort();

    expect(names.toSet(), {'Отпуск_1.JPG', 'Отпуск_2.JPG', 'notes.txt'});
    expect(command, isNotNull);
  });
}
