import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/view/common/split_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разделитель панелей: перетаскивание и возврат в середину.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)]);
  });

  Future<void> buildApp(WidgetTester tester, {double ratio = 0.3}) async {
    final settings = AppSettings(
      left: PanelSettings.defaults('/home'),
      right: PanelSettings.defaults('/home'),
      splitRatio: ratio,
    );
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Середина области захвата разделителя.
  Offset dividerCenter(WidgetTester tester) {
    final split = tester.getRect(find.byType(SplitView));
    return Offset(split.left + split.width * app.splitRatio, split.center.dy);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    // Отложенная запись настроек не должна остаться висеть после теста.
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('щелчок средней кнопкой ставит разделитель в середину', (tester) async {
    await buildApp(tester);
    expect(app.splitRatio, 0.3);

    await tester.tapAt(dividerCenter(tester), buttons: kTertiaryButton);
    await settle(tester);

    expect(app.splitRatio, 0.5);
  });

  testWidgets('двойной клик делает то же самое', (tester) async {
    await buildApp(tester, ratio: 0.7);

    final center = dividerCenter(tester);
    await tester.tapAt(center);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(center);
    await settle(tester);

    expect(app.splitRatio, 0.5);
  });

  testWidgets('щелчок мимо разделителя ничего не двигает', (tester) async {
    await buildApp(tester);
    final split = tester.getRect(find.byType(SplitView));

    // Середина левой панели — до разделителя далеко.
    await tester.tapAt(Offset(split.left + 40, split.center.dy), buttons: kTertiaryButton);
    await settle(tester);

    expect(app.splitRatio, 0.3);
  });

  testWidgets('новое положение переживает перезапуск', (tester) async {
    await buildApp(tester);

    await tester.tapAt(dividerCenter(tester), buttons: kTertiaryButton);
    await settle(tester);

    // Разделитель — часть сохраняемого состояния, как и всё остальное в окне.
    expect(app.settings.splitRatio, 0.5);
  });

  testWidgets('команда видна в списке команд и приглушена, когда двигать нечего', (tester) async {
    await buildApp(tester, ratio: 0.5);

    final command = app.commands.find(CenterSplitCommand.commandId)!;
    expect(command.label, 'Center split');
    // Уже посередине — делать нечего.
    expect(app.commands.isExecutable(command), isFalse);

    app.setSplitRatio(0.3);
    expect(app.commands.isExecutable(command), isTrue);

    // Смена доли запланировала запись настроек — дать ей случиться.
    await settle(tester);
  });
}
