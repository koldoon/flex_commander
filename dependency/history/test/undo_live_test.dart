import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Cmd-Z` живьём: скопировали — отменили (`docs/spec/operation-history.md`).
void main() {
  late AppRuntime runtime;
  late InMemoryTreeProvider provider;

  Future<void> open(WidgetTester tester) async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.directory('/dest'),
    ])..home = '/home';

    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/dest')),
    );

    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  /// Даёт доработать асинхронной части: работа, перечитывание панелей.
  Future<void> settle(WidgetTester tester) async {
    for (var step = 0; step < 6; step++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Сочетание — тем же разбором, каким его получает клавиатура.
  Future<void> combination(WidgetTester tester, String keys) async {
    runtime.commands.dispatch(KeyCombination.parse(keys));
    await tester.pumpAndSettle();
  }

  Future<bool> exists(String path) async => await provider.resolvePath().run(path) != null;

  /// Копирует строку под курсором в соседнюю панель — как это делает человек.
  Future<void> copyToDest(WidgetTester tester) async {
    runtime.app.left.setCursorToName('notes.txt');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.f5);
    await press(tester, LogicalKeyboardKey.enter);
    await settle(tester);
  }

  /// Соглашается в окне подтверждения отката.
  Future<void> agree(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FcButton, 'Undo').last);
    await settle(tester);
  }

  testWidgets('F7 создал каталог, Cmd-Z его убрал', (tester) async {
    await open(tester);

    // Каталог заводится той же работой, что и по `F7`.
    await runtime.app.runOperation().run(
      const OperationSpec(
        kind: FileOperations.makeDirectory,
        destination: Destination.path('/home'),
        options: {FileOperations.name: '111'},
      ),
    );
    await settle(tester);
    expect(await exists('/home/111'), isTrue);

    await combination(tester, 'Cmd-Z');
    expect(find.textContaining('delete 1 object'), findsOneWidget);
    await agree(tester);

    expect(await exists('/home/111'), isFalse);
    // Работа кончилась — окно ушло вместе с ней: висящее окно выглядит как
    // зависшая отмена (живой разбор 25 сентября 2026).
    expect(runtime.app.view.dialogs, isEmpty);
  });

  testWidgets('Cmd-Z отменяет одну работу за другой, а не упирается в себя', (tester) async {
    await open(tester);

    // Создали каталог, потом рядом переименовали файл — две работы подряд.
    await runtime.app.runOperation().run(
      const OperationSpec(
        kind: FileOperations.makeDirectory,
        destination: Destination.path('/home'),
        options: {FileOperations.name: '111'},
      ),
    );
    await runtime.app.runOperation().run(
      const OperationSpec(
        kind: FileOperations.rename,
        targets: Targets.paths(['/home/notes.txt']),
        options: {FileOperations.name: 'renamed.txt'},
      ),
    );
    await settle(tester);

    await combination(tester, 'Cmd-Z');
    await agree(tester);
    expect(await exists('/home/notes.txt'), isTrue, reason: 'переименование отменилось');
    expect(await exists('/home/111'), isTrue, reason: 'до каталога ещё не дошли');

    // Вторая отмена берётся за предыдущую работу, а не за саму отмену.
    await combination(tester, 'Cmd-Z');
    await agree(tester);

    expect(await exists('/home/111'), isFalse, reason: 'дошла очередь и до каталога');
  });

  testWidgets('F5 скопировал, Cmd-Z вернул приёмник к прежнему виду', (tester) async {
    await open(tester);
    await copyToDest(tester);
    expect(await exists('/dest/notes.txt'), isTrue);

    await combination(tester, 'Cmd-Z');

    // Окно говорит, что именно произойдёт, — а не «уверены?».
    expect(find.textContaining('delete 1 object'), findsOneWidget);
    await agree(tester);

    expect(await exists('/dest/notes.txt'), isFalse);
    expect(await exists('/home/notes.txt'), isTrue, reason: 'источник копирование не трогало');
  });

  testWidgets('удаление мимо корзины отменить нельзя, и об этом говорят', (tester) async {
    await open(tester);
    runtime.app.left.setCursorToName('notes.txt');
    await tester.pumpAndSettle();

    // Shift-F8 — удаление мимо корзины.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(await exists('/home/notes.txt'), isFalse);

    await combination(tester, 'Cmd-Z');

    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(await exists('/home/notes.txt'), isFalse, reason: 'ни одного изменения на диске');
  });

  testWidgets('F8 в корзину — и Cmd-Z достаёт обратно', (tester) async {
    await open(tester);
    runtime.app.left.setCursorToName('notes.txt');
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.f8);
    await press(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(await exists('/home/notes.txt'), isFalse);

    await combination(tester, 'Cmd-Z');
    expect(find.textContaining('return 1 object from Trash'), findsOneWidget);
    await agree(tester);

    expect(await exists('/home/notes.txt'), isTrue);
  });
}
