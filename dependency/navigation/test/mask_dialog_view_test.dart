import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно маски проверяется целиком: от клавиши до пометки в панели.
void main() {
  late AppController app;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/main.dart', size: 1),
      FakeEntry.file('/home/util.dart', size: 1),
      FakeEntry.file('/home/readme.md', size: 1),
      FakeEntry.file('/home/notes.txt', size: 1),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: [const Navigation()], settings: settings)).app;
  });

  final input = find.byWidgetPredicate((widget) => widget is TextField && widget.enabled != false);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Нажимает `+` так, как это делает клавиатура мака: на основном ряду это
  /// `Shift-=`.
  Future<void> pressPlus(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  Set<String> marked() => app.left.selection.names;

  testWidgets('«+» открывает окно с пустым полем в фокусе', (tester) async {
    await pumpApp(tester);

    await pressPlus(tester);

    expect(find.text('Select by mask'), findsWidgets);
    expect(input, findsOneWidget);
    final editable = tester.widget<EditableText>(find.descendant(of: input, matching: find.byType(EditableText)));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('счётчик показывает совпавшее, пока маску набирают', (tester) async {
    await pumpApp(tester);
    await pressPlus(tester);

    // Пока пусто — молчит: «0 of 5» на пустом поле было бы ложной тревогой.
    expect(find.textContaining(' of '), findsNothing);

    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();

    // Пять объектов без «..»: каталог и четыре файла.
    expect(find.text('2 of 5'), findsOneWidget);
  });

  testWidgets('Enter помечает совпавшее и закрывает окно', (tester) async {
    await pumpApp(tester);
    await pressPlus(tester);

    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FcButton, 'Mark'));
    await tester.pumpAndSettle();

    expect(marked(), {'main.dart', 'util.dart'});
    expect(input, findsNothing, reason: 'окно закрылось');
  });

  testWidgets('применённая маска предлагается в следующий раз', (tester) async {
    await pumpApp(tester);
    await pressPlus(tester);
    await tester.enterText(input, '*.dart');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FcButton, 'Mark'));
    await tester.pumpAndSettle();

    await pressPlus(tester);

    // Набирать ту же маску заново не нужно: она в списке под полем.
    expect(find.widgetWithText(FcPickList, '*.dart'), findsOneWidget);
  });
}
