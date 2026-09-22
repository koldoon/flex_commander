import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно редактора тем: роли полями формы настроек
/// (`docs/spec/theme-editor.md`).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> openEditor(WidgetTester tester, {Size size = const Size(900, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    runtime.app.commands.run(EditThemeCommand.commandId);
    await tester.pumpAndSettle();
  }

  /// Подпись поля: набрана разметкой, и обычный `find.text` её не видит.
  Finder role(String title) => find.text(title, findRichText: true);

  /// Поле ввода этой роли — в её же блоке.
  Finder editorOf(String title) => find.descendant(
    of: find.ancestor(of: role(title), matching: find.byType(Column)).first,
    matching: find.byType(FcTextField),
  );

  testWidgets('кнопка «Edit» в настройках открывает редактор', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    // Кнопка стоит рядом с выбором темы — там её и ищут.
    await tester.tap(find.widgetWithText(FcButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsWidgets);
    // Разделы — группы контракта: цвета отдельно, размеры отдельно.
    expect(find.text('File list'), findsWidgets);
    expect(find.text('Panel sizes'), findsWidgets);
    expect(find.text('Fonts'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 20));
  });

  /// Кнопка при этой настройке, а не одноимённая у соседней: «New» есть и у
  /// наборов выбора.
  Finder buttonIn(String setting, String label) => find.descendant(
    of: find.ancestor(of: role(setting), matching: find.byType(Column)).first,
    matching: find.widgetWithText(FcButton, label),
  );

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
  }

  testWidgets('«New» складывает своё оформление из нынешнего и переходит на него', (tester) async {
    await openSettings(tester);

    // Правка, ради которой тему и складывают.
    runtime.app.commands.run(EditThemeCommand.commandId);
    await tester.pumpAndSettle();
    await tester.enterText(editorOf('Cursor background').first, '#FF2D6CDF');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(buttonIn('Theme', 'New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FcTextField).last, 'My dark');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(runtime.app.theme.current.title, 'My dark');
    // Копией нынешних правок: «New» нажимают, доведя оформление до нужного.
    expect(runtime.app.theme.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    // И выбор запомнен — как всякий выбор темы (§13).
    expect(
      runtime.app.settings.modules.scope('fc.default_theme').section(ThemeSettings.new).themeId,
      runtime.app.theme.current.id,
    );

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('«Delete» убирает своё оформление и не трогает встроенное', (tester) async {
    await openSettings(tester);

    // На встроенной теме убирать нечего: кнопка приглушена.
    expect(tester.widget<FcButton>(buttonIn('Theme', 'Delete')).onPressed, isNull);

    await tester.tap(buttonIn('Theme', 'New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FcTextField).last, 'My dark');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(buttonIn('Theme', 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete theme'), findsWidgets, reason: 'согласия спрашивают окном');
    // Согласие спрашивают окном — и кнопка «Delete» в нём своя.
    await tester.tap(
      find.descendant(of: find.byType(CommandDialogConfirm), matching: find.widgetWithText(FcButton, 'Delete')),
    );
    await tester.pump();

    expect(runtime.app.theme.available.map((theme) => theme.title), isNot(contains('My dark')));
    expect(runtime.app.theme.current.id, 'default');

    await tester.pumpAndSettle();
  });

  testWidgets('подпись роли выведена из её имени, а не написана руками', (tester) async {
    await openEditor(tester);

    // `windowBackground` → «Window background»: полторы сотни подписей означали
    // бы полторы сотни строк перевода, которые никто не прочитает.
    expect(role('Window background'), findsOneWidget);
    expect(role('Cursor background'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('правка цвета перекрашивает приложение сразу', (tester) async {
    await openEditor(tester);

    await tester.enterText(editorOf('Cursor background').first, '#FF2D6CDF');
    await tester.pumpAndSettle();

    expect(runtime.app.theme.current.colors.cursorBackground, const Color(0xFF2D6CDF));
    // Кнопки «Применить» нет: правка уже на экране (`settings-window.md`, §6).
    expect(find.widgetWithText(FcButton, 'Apply'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('«Reset all» возвращает оформление и говорит, сколько вернул', (tester) async {
    await openEditor(tester);

    await tester.enterText(editorOf('Cursor background').first, '#FF2D6CDF');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FcButton, 'Reset all roles'));
    // Обычным `pump`, а не `pumpAndSettle`: тост живёт две секунды, и
    // промотанное до покоя время его уже погасит.
    await tester.pump();

    expect(runtime.app.theme.current.colors.cursorBackground, isNot(const Color(0xFF2D6CDF)));
    // Кнопка в подвале, а меняется от неё весь экран: без ответа нажатие
    // неотличимо от промаха.
    expect(runtime.app.toasts.current?.message, 'Reset 1 role');
    // И в поле — то, что в теме, а не набранное: правка прошла мимо полей.
    expect(tester.widget<FcTextField>(editorOf('Cursor background').first).controller.text, isNot('#FF2D6CDF'));

    await tester.pumpAndSettle();
  });

  testWidgets('просветы вокруг линейки равны — с поправкой на пустоту над буквами', (tester) async {
    await openEditor(tester);

    // Две соседние настройки: отбор ставит их рядом, и мерить есть что.
    await tester.enterText(find.byType(FcTextField).first, 'panel b');
    await tester.pumpAndSettle();

    const metrics = DefaultMetrics();
    final divider = tester.getRect(
      find.byWidgetPredicate((widget) => widget is Container && widget.color == const DefaultColors().columnDivider),
    );
    final above = tester.getRect(find.byType(FcColorField).first);
    final below = tester.getRect(role('Panel border'));

    // Под полем — столько, сколько назначено.
    expect(divider.top - above.bottom, closeTo(metrics.sectionEntryGap, 0.5));
    // А над подписью — меньше на пустоту, которую строка несёт над буквами:
    // на экране оба просвета выглядят одинаково.
    expect(below.top - divider.bottom, closeTo(metrics.sectionEntryGap - metrics.fontCapInset, 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('последняя настройка не липнет к кромке плашки', (tester) async {
    await openEditor(tester);

    await tester.enterText(find.byType(FcTextField).first, 'window background');
    await tester.pumpAndSettle();

    const metrics = DefaultMetrics();
    final plate = tester.getRect(find.byType(FcPlate).first);
    final field = tester.getRect(find.byType(FcColorField).first);

    // До кромки — столько же, сколько до линейки: своего поля у плашки меньше.
    expect(plate.bottom - metrics.strokeWidth - field.bottom, closeTo(metrics.sectionEntryGap, 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('поиск находит роль по её имени', (tester) async {
    await openEditor(tester);

    await tester.enterText(find.byType(FcTextField).first, 'cursor');
    await tester.pumpAndSettle();

    expect(role('Cursor background'), findsOneWidget);
    expect(role('Window background'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });
}
