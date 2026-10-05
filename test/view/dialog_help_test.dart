import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// «?» в заголовке окна — свойство рамы: есть `onHelp` — есть знак, щелчок и
/// `F1` зовут справку (`docs/spec/multi-rename.md`, §14.1).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  Finder helpSign() => find.descendant(of: find.byType(DialogFrame), matching: find.byKey(DialogFrame.helpKey));

  testWidgets('окно со справкой — знак «?», щелчок и F1 её зовут', (tester) async {
    await pumpApp(tester);
    var asked = 0;
    late final String id;
    id = runtime.app.view.showDialog(
      DialogSpec(
        title: 'With help',
        takesFocus: true,
        content: const Text('body'),
        onDismiss: () => runtime.app.view.closeDialog(id),
        onHelp: () => asked++,
      ),
    );
    await tester.pumpAndSettle();

    expect(helpSign(), findsOneWidget);

    await tester.tap(helpSign());
    await tester.pumpAndSettle();
    expect(asked, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(asked, 2, reason: 'F1 в окне — его справка, а не справка приложения');
  });

  testWidgets('окно без справки — знака нет, F1 в нём ничего не открывает', (tester) async {
    await pumpApp(tester);
    late final String id;
    id = runtime.app.view.showDialog(
      DialogSpec(
        title: 'Plain',
        takesFocus: true,
        content: const Text('body'),
        onDismiss: () => runtime.app.view.closeDialog(id),
      ),
    );
    await tester.pumpAndSettle();

    expect(helpSign(), findsNothing);
  });

  testWidgets('кнопка заголовка под указателем залита акцентом во всю высоту полосы', (tester) async {
    await pumpApp(tester);
    late final String id;
    id = runtime.app.view.showDialog(
      DialogSpec(
        title: 'With help',
        takesFocus: true,
        content: const Text('body'),
        onDismiss: () => runtime.app.view.closeDialog(id),
        onHelp: () {},
      ),
    );
    await tester.pumpAndSettle();

    Color? fill(Key key) =>
        tester.widget<Container>(find.descendant(of: find.byKey(key), matching: find.byType(Container)).first).color;
    final colors = FcTheme.of(tester.element(find.byKey(DialogFrame.helpKey))).colors;
    final metrics = FcTheme.of(tester.element(find.byKey(DialogFrame.helpKey))).metrics;

    expect(fill(DialogFrame.helpKey), isNull);
    expect(tester.getSize(find.byKey(DialogFrame.helpKey)).height, metrics.dialogTitleHeight);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byKey(DialogFrame.helpKey)));
    await tester.pumpAndSettle();
    expect(fill(DialogFrame.helpKey), colors.dialogTitleButtonHover);
    expect(fill(DialogFrame.closeKey), isNull, reason: 'подсвечена только та, что под указателем');

    await mouse.moveTo(tester.getCenter(find.byKey(DialogFrame.closeKey)));
    await tester.pumpAndSettle();
    expect(fill(DialogFrame.helpKey), isNull);
    expect(fill(DialogFrame.closeKey), colors.dialogTitleButtonHover);
  });
}
