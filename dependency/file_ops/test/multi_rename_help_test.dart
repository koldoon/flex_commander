import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Справка по маскам группового переименования (`docs/spec/multi-rename.md`,
/// §14).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/a.txt', size: 1)])
        ..home = '/home',
      modules: [const Navigation(), const FileOps()],
      backend: [const FileOps()],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var step = 0; step < 6; step++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('у окна переименования есть справка, и она открывается поверх него', (tester) async {
    runtime.app.left.setCursorToName('a.txt');
    await runtime.commands.create(MultiRenameCommand.commandId)!.executeWith();
    await settle(tester);
    final rename = runtime.app.view.dialogs.single;
    expect(rename.onHelp, isNotNull);

    rename.onHelp!();
    await settle(tester);

    final help = runtime.app.view.dialogs.last;
    expect(help.title, 'Rename mask help');
    expect(help.parent, isNotNull, reason: 'дочернее окно — форма под ним остаётся');
    expect(help.onHelp, isNull, reason: 'у справки своей справки нет');
    expect(runtime.app.view.dialogs, hasLength(2));
  });

  test('текст — на языке приложения, с рецептом счётчика и таблицей записей', () {
    final english = multiRenameHelpText('en');
    expect(english, contains('Number the files'));
    expect(english, contains('[C:3]'));
    expect(english, contains('| `[N2-5]` |'));

    final russian = multiRenameHelpText('ru');
    expect(russian, contains('Пронумеровать файлы'));
    expect(russian, contains('[C:3]'));
  });

  testWidgets('показ — свёрстанным документом', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: const Scaffold(body: Center(child: MultiRenameHelp(language: 'en'))),
      ),
    );
    await settle(tester);

    expect(find.byType(FcMarkdownView), findsOneWidget);
    expect(find.textContaining('Number the files', findRichText: true), findsWidgets);
  });
}
