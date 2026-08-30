import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
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

  group('синонимы команд', () {
    /// Все установленные команды — палитра берёт синонимы у них же.
    List<AppCommand> installed() => runtime.commands.installed;

    /// Кто найдётся по такому запросу тем же отбором, каким ищет палитра.
    ///
    /// Модуль нарочно не подаётся: проверяются синонимы, и попадание по
    /// названию модуля здесь только запутало бы ответ.
    List<String> foundBy(String query) => [
      for (final command in installed())
        if (matchCommand(query, label: command.label, keywords: command.keywords) != null) command.label,
    ];

    test('синоним, который и так находится по названию, — мёртвый груз', () {
      final dead = <String>[];
      for (final command in installed()) {
        for (final keyword in command.keywords) {
          // Тот же отбор, но без синонимов: нашлось — значит слово ничего не
          // добавляет, а список синонимов растёт и вводит в заблуждение.
          if (matchCommand(keyword, label: command.label) != null) {
            dead.add('${command.label}: $keyword');
          }
        }
      }

      expect(dead, isEmpty, reason: 'эти слова находятся и без синонимов');
    });

    test('синонимы записаны строчными и без пустых', () {
      for (final command in installed()) {
        for (final keyword in command.keywords) {
          expect(keyword, keyword.toLowerCase(), reason: '${command.label}: регистр в запросе всё равно не важен');
          expect(keyword.trim(), isNotEmpty, reason: '${command.label}: пустой синоним');
        }
      }
    });

    test('упаковщики находятся по делу, а не только по формату', () {
      // Ровно та жалоба, с которой синонимы и завелись: «Mk Tar» умеет
      // `.tar.gz`, а на `gz` не отзывалась.
      expect(foundBy('gz'), containsAll(['Mk Tar', 'Mk Gz']));
      expect(foundBy('compress'), containsAll(['Mk Zip', 'Mk 7z', 'Mk Tar', 'Mk Gz']));
      expect(foundBy('archive'), containsAll(['Mk Zip', 'Mk 7z', 'Mk Tar', 'Mk Gz']));
    });

    test('слова другой школы приводят к тому же делу', () {
      expect(foundBy('folder'), contains('Mk Dir'));
      expect(foundBy('preferences'), contains('Settings'));
      expect(foundBy('shortcuts'), contains('Help'));
      expect(foundBy('refresh'), contains('Reload'));
      expect(foundBy('dotfiles'), contains('Hidden files'));
      expect(foundBy('dark'), contains('Switch theme'));
    });

    test('чего команда не умеет, по тому и не находится', () {
      // Переименования в приложении нет вовсе: `Move` требует каталог, другого
      // имени ей не задать. Привести к ней по слову `rename` значило бы
      // соврать — человек нашёл бы команду и не смог сделать то, что искал.
      expect(foundBy('rename'), isNot(contains('Move')));
    });
  });

  testWidgets('Cmd-Shift-P открывает палитру', (tester) async {
    await openPalette(tester);

    expect(find.byType(FcCommandPalette), findsOneWidget);
    expect(rows(tester), isNotEmpty);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('высота списка — целое число строк, без подрезанной снизу', (tester) async {
    // Высота нарочно некруглая: окно тянется во всю высоту экрана, и остаток от
    // деления резал бы нижнюю строку пополам.
    await openPalette(tester, size: const Size(900, 703));

    final theme = FcTheme.of(tester.element(find.byType(FcPickList)));
    final line = theme.metrics.rowHeight + theme.metrics.rowGap;
    final list = tester.getRect(find.byType(FcPickList));

    expect(list.height % line, moreOrLessEquals(0, epsilon: 0.01), reason: 'список кончается целой строкой');

    // И под ним остаётся отступ — тот же, каким поле отбито от заголовка.
    final window = tester.getRect(find.descendant(of: find.byType(DialogFrame), matching: find.byType(IntrinsicWidth)));
    expect(window.bottom - list.bottom, moreOrLessEquals(theme.metrics.dialogContentTopPadding, epsilon: 0.5));

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

  testWidgets('рядом с названием стоит описание команды, а не модуль', (tester) async {
    await openPalette(tester);
    await tester.enterText(field(), 'hidden');
    await tester.pumpAndSettle();

    final command = runtime.commands.find('panel.toggleHidden')!;
    expect(command.description, isNotEmpty, reason: 'иначе проверять нечего');
    expect(rows(tester).first, contains(command.description));
    // Модуль в строке не показывается: он сообщал ровно то, что и так видно по
    // названию.
    expect(rows(tester).first, isNot(contains(runtime.resolve<CommandRegistry>().ownerOf(command.id))));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('команда без описания показывается одним названием', (tester) async {
    await openPalette(tester);
    // У «Cursor up» объяснять нечего, и подставлять туда модуль ради
    // заполненной колонки нельзя.
    final command = runtime.commands.find('panel.cursor.up')!;
    expect(command.description, isEmpty, reason: 'иначе проверять нечего');

    await tester.enterText(field(), command.label);
    await tester.pumpAndSettle();

    expect(rows(tester).first.trim(), command.label);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('по названию модуля команда по-прежнему находится', (tester) async {
    // Модуль переехал в невидимые признаки, к синонимам: читать его в строке
    // нечего, а искать по нему надо.
    await openPalette(tester);
    await tester.enterText(field(), 'navigation');
    await tester.pumpAndSettle();

    expect(rows(tester), isNotEmpty);
    expect(find.textContaining('Nothing found'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('PgDn двигает выбор на страницу, PgUp у края упирается в первую', (tester) async {
    await openPalette(tester);

    final theme = FcTheme.of(tester.element(find.byType(FcPickList)));
    final line = theme.metrics.rowHeight + theme.metrics.rowGap;
    // Строк в обзоре — столько же, сколько намерил себе сам список.
    final visible = (tester.getRect(find.byType(FcPickList)).height / line).round();
    expect(visible, greaterThan(3), reason: 'иначе страницы не отличить от строки');

    /// Которая строка подсвечена.
    int selected() {
      final rows = tester.widgetList<Container>(
        find.descendant(of: find.byType(FcPickList), matching: find.byType(Container)),
      );
      return rows.toList().indexWhere((row) => row.color == theme.colors.cursorBackground);
    }

    expect(selected(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    // Видимые строки минус одна: перекрытие не даёт потерять место, где
    // остановился взгляд.
    expect(selected(), visible - 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(selected(), 0);

    // И ещё раз вверх — упор, а не заворот в конец списка.
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(selected(), 0);

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
