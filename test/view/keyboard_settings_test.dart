import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/keymaps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Раздел «Keyboard» в окне настроек: устроен как раздел оформления
/// (`docs/spec/keymaps.md`, §4).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/docs')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  /// Открыть настройки и отобрать раздел клавиш: так до него не надо
  /// долистывать.
  Future<void> openKeyboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(of: find.byType(FcSettingsForm), matching: find.byType(TextField)).first,
      'keymap',
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FcButton, label));
    await tester.pumpAndSettle();
  }

  /// Набрать имя в окне и подтвердить.
  Future<void> nameIt(WidgetTester tester, String name) async {
    await tester.enterText(find.descendant(of: find.byType(CommandDialogForm), matching: find.byType(TextField)), name);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save the keymap');
  }

  testWidgets('раздел зовётся по делу, а не именем модуля', (tester) async {
    await openKeyboard(tester);

    expect(find.text('Keyboard'), findsWidgets);
    expect(find.text('Presets'), findsNothing, reason: 'раздел наборов убран');
  });

  testWidgets('набор складывается и сразу виден в списке', (tester) async {
    await openKeyboard(tester);
    expect(find.text('Default'), findsWidgets, reason: 'пустой выбор должен быть настоящим вариантом');

    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    expect(runtime.app.keymaps.single.name, 'Дом');
    expect(runtime.app.keymap, 'Дом');
    // Схемы строятся один раз, и без пересборки нового набора в списке бы не
    // было (`docs/spec/keymaps.md`, §4).
    expect(find.text('Дом'), findsWidgets, reason: 'набор не появился, не закрывая окна');
  });

  testWidgets('занятое имя — ошибка в том же окне', (tester) async {
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    expect(find.text('There is a keymap with this name already'), findsOneWidget);
    expect(runtime.app.keymaps, hasLength(1), reason: 'второй «Дом» затёр бы первый');
  });

  testWidgets('у Default удалять и выгружать нечего', (tester) async {
    await openKeyboard(tester);

    // Приглушены, а не спрятаны: действие есть, просто сейчас неприменимо.
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Delete')).onPressed, isNull);
    expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Export')).onPressed, isNull);
  });

  bool alive(WidgetTester tester, String label) =>
      tester.widget<FcButton>(find.widgetWithText(FcButton, label)).onPressed != null;

  testWidgets('выбранный набор оживляет кнопки при списке', (tester) async {
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    expect(alive(tester, 'Edit'), isTrue);
    expect(alive(tester, 'Delete'), isTrue);
    expect(alive(tester, 'Export'), isTrue);
  });

  testWidgets('выбор набора в списке оживляет кнопки тут же', (tester) async {
    // Кнопки знают о выбранном из схемы, а схема строится один раз: без
    // пересборки они остались бы приглушёнными до следующего открытия окна.
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');
    await tapButton(tester, 'New');
    await nameIt(tester, 'Работа');

    // Снять выбор и выбрать снова — списком, как это делает человек.
    Keymaps(app: runtime.app, builtIn: () => runtime.resolve<KeymapCatalog>().keymaps).select('');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FcSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дом').last);
    await tester.pumpAndSettle();

    expect(runtime.app.keymap, 'Дом');
    expect(alive(tester, 'Delete'), isTrue, reason: 'выбрали свой набор, а удалить его нечем');
    expect(alive(tester, 'Export'), isTrue);
  });

  testWidgets('удаление спрашивает и убирает набор', (tester) async {
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'Delete');
    expect(find.text('Delete «Дом»? Keys return to Default.'), findsOneWidget);
    // Кнопку вопроса, а не ту, что подняла окно: подписи у них одинаковые.
    await tester.tap(
      find.descendant(of: find.byType(CommandDialogConfirm), matching: find.widgetWithText(FcButton, 'Delete')),
    );
    await tester.pumpAndSettle();

    expect(runtime.app.keymaps, isEmpty);
    expect(runtime.app.keymap, isEmpty);
  });

  testWidgets('выгрузка показывает дерево от дома, а не поле пути', (tester) async {
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'Export');

    expect(find.byType(FcDirectoryTree), findsOneWidget, reason: 'каталог набирают руками, а не выбирают');
    expect(find.text('Home'), findsOneWidget, reason: 'дерево должно начинаться с дома');
    expect(find.text('File name'), findsOneWidget, reason: 'имя файла спрашивают тут же');
  });

  testWidgets('дерево открыто от корня и ходит щелчком', (tester) async {
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');
    await tapButton(tester, 'Export');

    // Ищем **в дереве**: за окном стоит панель, и там этот каталог тоже виден.
    Finder inTree(String name) => find.descendant(of: find.byType(FcDirectoryTree), matching: find.text(name));

    // Корень раскрыт сразу: пустое дерево не сказало бы ничего.
    expect(inTree('docs'), findsOneWidget, reason: 'ветвей дома не видно');

    // Щелчок по выбранной раскрытой ветви её сворачивает — иначе закрыть её
    // мышью было бы нечем.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(inTree('docs'), findsNothing);
  });

  testWidgets('отказ окна файла говорится тостом, а окно остаётся', (tester) async {
    // Сообщение внутри формы двигало бы поля ровно тогда, когда в них
    // собираются что-то поправить (`docs/widgets.md`).
    await openKeyboard(tester);
    await tapButton(tester, 'Import');

    await tester.enterText(
      find.descendant(of: find.byType(CommandDialogForm), matching: find.byType(TextField)),
      'нет-такого.json',
    );
    await tester.pumpAndSettle();
    // Кнопку окна, а не ту, что его подняло: подписи у них одинаковые.
    await tester.tap(
      find.descendant(of: find.byType(CommandDialogForm), matching: find.widgetWithText(FcButton, 'Import')),
    );
    // Настоящим временем, а не промотанным: ответ идёт через границу, и ждёт
    // его обычный цикл событий. А до покоя мотать нельзя — тост живёт две
    // секунды, и промотанное время его погасит.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(runtime.app.toasts.current?.failed, isTrue, reason: 'об отказе не сказано');
    expect(find.byType(FcDirectoryTree), findsOneWidget, reason: 'окно закрылось, а поправить негде');
    await tester.pumpAndSettle();
  });

  testWidgets('встроенный набор выбирается, но не правится', (tester) async {
    await openKeyboard(tester);

    await tester.tap(find.byType(FcSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mc').last);
    await tester.pumpAndSettle();

    expect(runtime.app.keymap, 'mc');
    expect(alive(tester, 'Export'), isTrue, reason: 'выгрузить встроенный можно — так его делают своим');
    expect(alive(tester, 'Delete'), isFalse, reason: 'встроенный не свой');
  });

  testWidgets('отказ ничего не убирает', (tester) async {
    await openKeyboard(tester);
    await tapButton(tester, 'New');
    await nameIt(tester, 'Дом');

    await tapButton(tester, 'Delete');
    await tapButton(tester, 'Cancel');

    expect(runtime.app.keymaps, hasLength(1));
  });

  testWidgets('Edit открывает окно клавиш', (tester) async {
    await openKeyboard(tester);

    await tapButton(tester, 'Edit');

    expect(find.text('Reset all keys'), findsOneWidget, reason: 'окна клавиш не видно');
  });
}
