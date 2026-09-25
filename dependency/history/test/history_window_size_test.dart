import 'package:fc_api/fc_api.dart';
import 'package:fc_history/fc_history.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно истории в **тесном** окне: список ужимается, а не вылезает
/// (`docs/spec/operation-history.md`, §10).
void main() {
  testWidgets('длинный список не переполняет окно', (tester) async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home';
    final AppRuntime runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(
        left: PanelSettings.defaults('/home'),
        right: PanelSettings.defaults('/home'),
        // Окно уже растягивали: высоту ему задаёт рама, и содержимое обязано
        // в неё уложиться (`docs/spec/dialog-resize.md`, §6).
        dialogs: {ShowHistoryCommand.commandId: DialogState(width: 600, height: 260)},
      ),
    );
    await runtime.app.start();

    // Десяток работ: в невысокое окно они не влезают.
    for (var at = 0; at < 10; at++) {
      await runtime.app.runOperation().run(
        OperationSpec(
          kind: FileOperations.makeDirectory,
          destination: const Destination.path('/home'),
          options: {FileOperations.name: 'dir$at'},
        ),
      );
    }

    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    await runtime.commands.runAndWait(ShowHistoryCommand.commandId);
    await tester.pumpAndSettle();

    expect(find.text('Operation history'), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'список ужимается, а не вылезает за раму');
  });
}
