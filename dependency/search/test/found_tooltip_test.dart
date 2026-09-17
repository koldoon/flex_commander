import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Имя находки договаривается подсказкой (`docs/spec/tooltips.md`, §7).
void main() {
  const long = 'невероятно длинное имя найденного файла, которому не хватит ширины окна.dart';
  const short = 'util.dart';

  late AppController app;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/$short', size: 1),
      FakeEntry.file('/home/$long', size: 1),
    ]);
    app = (await testApp(provider: provider, modules: featureModules())).app;
  });

  Finder tipOf(String text) => find.ancestor(of: find.text(text).first, matching: find.byType(FcTooltip));

  testWidgets('длинное имя находки договаривается, короткое — молчит', (tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Именно поле маски: живых полей в окне несколько, а внизу экрана стоит
    // ещё и командная строка. Маска — то поле, которое просит фокус себе.
    await tester.enterText(
      find.descendant(
        of: find.byType(FindFilesForm),
        matching: find.byWidgetPredicate((widget) => widget is TextField && widget.autofocus),
      ),
      '*.dart',
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(tester.widget<FcTooltip>(tipOf(long).first).message, long);
    expect(tipOf(short), findsNothing, reason: 'поместилось — договаривать нечего');

    await disposeScreen(tester);
  });
}
