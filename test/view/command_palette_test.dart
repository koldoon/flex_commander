import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/commands/palette_command.dart';
import 'package:flex_commander/state/shell_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Палитра команд: всё, что приложение умеет сейчас, по названию.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])
        ..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> openPalette(WidgetTester tester, {Size size = const Size(900, 700)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-P'));
    await tester.pumpAndSettle();
  }

  Finder field() => find.descendant(of: find.byType(FcCommandPalette), matching: find.byType(TextField));

  /// Названия строк списка сверху вниз.
  List<String> rows(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: find.byType(FcCommandPalette), matching: find.byType(Text)),
    ))
      if (text.textSpan?.toPlainText().trim().isNotEmpty ?? false) text.textSpan!.toPlainText(),
  ];

  testWidgets('Cmd-Shift-P открывает палитру', (tester) async {
    await openPalette(tester);

    expect(find.byType(FcCommandPalette), findsOneWidget);
    expect(rows(tester), isNotEmpty);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('строка выбора идёт до краёв окна, а текст стоит под набранным', (tester) async {
    await openPalette(tester);
    await tester.enterText(field(), 'mkd');
    await tester.pumpAndSettle();

    // Именно в списке: «Mk Dir» есть и на кнопке `F7` внизу экрана.
    final title =
        find.descendant(of: find.byType(FcPickList), matching: find.textContaining('Mk Dir', findRichText: true)).first;
    final list = tester.getRect(find.byType(FcPickList));
    final row = tester.getRect(find.ancestor(of: title, matching: find.byType(GestureDetector)).first);

    // Строка выбора — во всю ширину: отбитая полями, она читалась бы как
    // плитка, а не как «эта строка списка».
    expect(row.left, list.left);
    expect(row.right, list.right);

    // А текст в ней — ровно под набранным в поле, иначе список выглядит
    // съехавшим относительно того самого поля, которое он дополняет.
    // Поле палитры, а не командная строка внизу экрана.
    final typed = tester.getRect(
      find.descendant(of: find.byType(FcCommandPalette), matching: find.byType(EditableText)),
    );
    expect(tester.getRect(title).left, moreOrLessEquals(typed.left, epsilon: 0.5));
    expect(list.width, greaterThan(typed.width), reason: 'поле отбито полями окна, а список — нет');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('набранное отбирает строки — по порядку букв, а не подряд', (tester) async {
    await openPalette(tester);
    // `mkd` находит `Mk Dir`: буквы идут по порядку, но не подряд.
    await tester.enterText(field(), 'mkd');
    await tester.pumpAndSettle();

    final found = rows(tester);
    expect(found, isNotEmpty);
    expect(found.first, contains('Mk Dir'));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('невыполнимой команды в списке нет', (tester) async {
    // «Wrap» принадлежит просмотрщику, а он не открыт: сделать этого сейчас
    // нельзя, и предлагать нечего.
    await openPalette(tester);
    await tester.enterText(field(), 'wrap');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing found'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Enter запускает выбранное и закрывает палитру', (tester) async {
    await openPalette(tester);
    await tester.enterText(field(), 'hidden');
    await tester.pumpAndSettle();

    final before = runtime.app.left.showHidden;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(FcCommandPalette), findsNothing);
    expect(runtime.app.left.showHidden, isNot(before), reason: 'команда выполнилась');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('стрелки двигают выбор', (tester) async {
    await openPalette(tester);
    await tester.enterText(field(), 'mark');
    await tester.pumpAndSettle();

    final first = rows(tester).first;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Запустилась вторая, а не первая: значит стрелка сдвинула выбор.
    final recent = runtime.app.settings.modules.scope('fc.shell').section(ShellSettings.new).recentCommands;
    expect(recent, isNotEmpty);
    expect(first, isNot(contains(recent.first)));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Esc закрывает', (tester) async {
    await openPalette(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(FcCommandPalette), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('недавние идут первыми, а следом всё остальное', (tester) async {
    runtime.app.settings.modules.scope('fc.shell').section(ShellSettings.new).recentCommands.add('panel.toggleHidden');
    await openPalette(tester);

    expect(rows(tester).first, contains('Hidden'));
    expect(rows(tester).length, greaterThan(3), reason: 'палитра остаётся и каталогом');

    await tester.pump(const Duration(milliseconds: 20));
  });

  test('запуск помнится между запусками приложения', () async {
    final command = runtime.commands.find(CommandPaletteCommand.commandId);
    expect(command, isNotNull);

    final saved = <String, dynamic>{};
    runtime.app.settings.modules.scope('fc.shell').section(ShellSettings.new).recentCommands.add('panel.up');
    runtime.app.settings.toMap(saved);

    expect((saved['modules'] as Map)['fc.shell'], containsPair('recentCommands', ['panel.up']));
  });
}
