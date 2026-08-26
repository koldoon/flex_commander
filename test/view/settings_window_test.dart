import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно настроек: то, что человек выбирает, — в одном месте.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> openSettings(WidgetTester tester, {Size size = const Size(900, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
  }

  TerminalSettings terminal() => (runtime.app.view.contentAt(ViewportPosition.bottom)! as CommandLineState).settings;

  testWidgets('F2 открывает настройки, разделы — по модулям', (tester) async {
    await openSettings(tester);

    expect(find.byType(FcSettingsForm), findsOneWidget);
    // Заголовки — названия модулей, как в справке.
    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Text viewer'), findsWidgets);
    // И поля под ними.
    expect(find.text('Typing goes to the command line'), findsOneWidget);
    expect(find.text('Wrap long lines'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('флаг переключается и доезжает до раздела настроек', (tester) async {
    await openSettings(tester);
    expect(terminal().typingGoesToLine, isFalse);

    await tester.tap(find.text('Typing goes to the command line'));
    await tester.pumpAndSettle();

    expect(terminal().typingGoesToLine, isTrue, reason: 'применяется сразу, без кнопки «Применить»');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('число берётся из поля, а не из головы', (tester) async {
    await openSettings(tester);

    final scrollback = find.ancestor(of: find.text('lines'), matching: find.byType(Row)).first;
    await tester.enterText(find.descendant(of: scrollback, matching: find.byType(TextField)), '4096');
    await tester.pumpAndSettle();

    expect(terminal().maxLines, 4096);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('состояние в настройках не показывается', (tester) async {
    terminal().history.add('ls -la');
    await openSettings(tester);

    // История команд, пути панелей и геометрия окна — это память приложения, а
    // не выбор человека: показать их полем значило бы предложить их править.
    Finder inForm(Finder finder) => find.descendant(of: find.byType(FcSettingsForm), matching: finder);
    expect(inForm(find.text('ls -la')), findsNothing);
    expect(inForm(find.text('history')), findsNothing);
    // Пути панелей за окном видны, а в самих настройках их нет.
    expect(inForm(find.textContaining('/home')), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Esc закрывает', (tester) async {
    await openSettings(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(FcSettingsForm), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  test('у каждого поля схемы есть ключ в разделе настроек', () {
    // Схема, разошедшаяся с данными, разошлась бы молча: поле писало бы в
    // объект, которого в файле нет, и настройка не пережила бы перезапуск.
    final pages = runtime.resolve<SettingsCatalog>().pages;
    expect(pages, isNotEmpty);

    // Все ключи, которые приложение действительно пишет: свои и разделов
    // модулей.
    final saved = <String, dynamic>{};
    runtime.app.settings.toMap(saved);
    final keys = <String>{
      ...saved.keys,
      for (final section in (saved['modules'] as Map).values) ...(section as Map).keys.cast<String>(),
    };

    for (final page in pages) {
      for (final field in page.build().fields) {
        expect(field.title, isNotEmpty, reason: 'поле без подписи не покажешь');
        expect(
          keys,
          contains(field.id),
          reason: 'поле «${field.title}» пишет в ${field.id}, а такого ключа в настройках нет',
        );
      }
    }
  });
}
