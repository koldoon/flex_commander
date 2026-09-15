import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/help_command.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Приложение знает о своей сборке (`docs/spec/build-info.md`).
void main() {
  late FakeClipboard clipboard;

  Future<AppController> start(WidgetTester tester, {BuildInfo? build}) async {
    clipboard = FakeClipboard();
    final app =
        (await testApp(
          provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
          modules: featureModules(),
          clipboard: clipboard,
          build: build,
        )).app;

    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('сведения о сборке доезжают до приложения', (tester) async {
    final app = await start(tester, build: const BuildInfo(version: '0.0.77', build: '128', architecture: 'arm64'));

    expect(app.build.version, '0.0.77');
    expect(app.build.describe(), '0.0.77 (build 128)');
  });

  testWidgets('не знает о себе ничего — и это не мешает работать', (tester) async {
    // Так живут прогон и `flutter run`: канала раннера нет, спрашивать некого.
    final app = await start(tester);

    expect(app.build.isKnown, isFalse);
    expect(app.left.currentPath, '/home');
  });

  testWidgets('справка показывает версию сборки', (tester) async {
    final app = await start(tester, build: const BuildInfo(version: '0.0.77', build: '128', architecture: 'arm64'));

    app.commands.run(HelpCommand.commandId);
    await tester.pumpAndSettle();

    expect(find.text('Application'), findsOneWidget);
    expect(find.text('0.0.77 (build 128)'), findsOneWidget);
    expect(find.text('arm64'), findsOneWidget);
  });

  testWidgets('не знающая себя сборка так и говорит, а не врёт про 1.0.0', (tester) async {
    final app = await start(tester);

    app.commands.run(HelpCommand.commandId);
    await tester.pumpAndSettle();

    expect(find.text('unknown — this build is not a release'), findsOneWidget);
  });

  testWidgets('версия уезжает в отчёт об ошибке', (tester) async {
    final app = await start(tester, build: const BuildInfo(version: '0.0.77', build: '128'));

    app.errors.report(StateError('сломалось'), StackTrace.current);
    await tester.pumpAndSettle();
    await app.errors.copyReport();

    final copied = clipboard.text ?? '';
    expect(copied, contains('Version: 0.0.77 (build 128)'));
  });
}
