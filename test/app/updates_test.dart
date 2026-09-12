import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_updater/fc_updater.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обновление в живом приложении: команда, настройка и кнопка рядом с ней
/// (`docs/spec/self-update.md`, §8-9).
void main() {
  late AppRuntime runtime;

  Future<void> start(WidgetTester tester) async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    runtime.commands.run('app.settings');
    await tester.pumpAndSettle();
    // Раздел обновлений — последний в оглавлении: модуль объявлен последним.
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();
  }

  testWidgets('команда обновления есть и выполнима', (tester) async {
    await start(tester);

    final command = runtime.commands.find(CheckForUpdatesCommand.commandId);
    expect(command, isNotNull);
    // Спросить можно всегда: сеть может не ответить, но это уже ответ.
    expect(runtime.commands.isExecutable(command!), isTrue);
  });

  testWidgets('в настройках есть флажок и кнопка рядом с ним', (tester) async {
    await start(tester);
    await openSettings(tester);

    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.widgetWithText(FcButton, 'Check now'), findsOneWidget);
  });

  testWidgets('кнопка жива и со снятым флажком', (tester) async {
    await start(tester);
    await openSettings(tester);

    // Снимаем флажок: отказ проверять по расписанию не значит отказа проверить
    // сейчас (`docs/spec/self-update.md`, §8).
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    final button = tester.widget<FcButton>(find.widgetWithText(FcButton, 'Check now'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('при запуске приложение в сеть не ходит', (tester) async {
    // Своей версии проверочная сборка не знает — канала раннера у неё нет, —
    // и стартовая проверка честно не начинается вовсе: ни запроса, ни таймера
    // (`docs/spec/self-update.md`, §11). Если бы начиналась, этот тест висел
    // бы на сети или падал на незакрытом таймере.
    await start(tester);
    await tester.pump(const Duration(seconds: 10));

    expect(runtime.app.toasts.current, isNull, reason: 'молчит — значит и не спрашивала');
  });
}
