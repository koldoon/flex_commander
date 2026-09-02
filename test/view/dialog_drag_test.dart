import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно команды отодвигается за полосу заголовка.
///
/// Окно берётся настоящее — «открыть путь» над левой панелью: у него есть и
/// поле ввода (проверить, что фокус от перетаскивания не страдает), и своя
/// область, от которой считается смещение.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/docs')])..home = '/home',
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
  });

  Future<void> openDialog(WidgetTester tester, {Size size = const Size(1200, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();

    runtime.commands.run(
      OpenPathCommand.commandId,
      CommandInvocation(parameters: {OpenPathCommand.panelParam: OpenPathCommand.leftPanel}),
    );
    await tester.pumpAndSettle();
  }

  Finder title() => find.text('Open path (left panel)');

  /// Само окно: `IntrinsicWidth` внутри рамы — рама занимает всю область.
  Rect window(WidgetTester tester) =>
      tester.getRect(find.descendant(of: find.byType(DialogFrame), matching: find.byType(IntrinsicWidth)));

  /// Тянуть мышью, шагами: одно движение только начинает протяжку, положение —
  /// дело последующих.
  Future<void> drag(WidgetTester tester, Finder handle, Offset by) async {
    final from = tester.getCenter(handle);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: from);
    await tester.pump();
    await mouse.down(from);
    await tester.pump(const Duration(milliseconds: 20));
    for (var step = 1; step <= 5; step++) {
      await mouse.moveTo(from + by * (step / 5));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();
  }

  testWidgets('за заголовок окно едет за указателем', (tester) async {
    await openDialog(tester);
    final before = window(tester);

    await drag(tester, title(), const Offset(120, -60));

    final after = window(tester);
    expect(after.left - before.left, moreOrLessEquals(120, epsilon: 0.5));
    expect(after.top - before.top, moreOrLessEquals(-60, epsilon: 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('за содержимое окно не едет', (tester) async {
    await openDialog(tester);
    final before = window(tester);

    // Поле ввода — не ручка: движение по нему значит своё.
    await drag(tester, dialogField(), const Offset(120, 0));

    expect(window(tester), before);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('за край окно целиком не уходит', (tester) async {
    await openDialog(tester);
    final metrics = FcTheme.of(tester.element(find.byType(DialogFrame))).metrics;

    await drag(tester, title(), const Offset(-5000, 0));

    final after = window(tester);
    // На экране осталась ухватистая часть — иначе окно было бы не вернуть:
    // тянут-то за заголовок.
    expect(after.right, greaterThanOrEqualTo(metrics.dialogDragKeepVisible - 0.5));
    // А полоса заголовка видна целиком: она внутри экрана по вертикали.
    expect(after.top, greaterThanOrEqualTo(-0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('окно приложения сузили — отодвинутое осталось достижимым', (tester) async {
    await openDialog(tester);
    final metrics = FcTheme.of(tester.element(find.byType(DialogFrame))).metrics;

    await drag(tester, title(), const Offset(500, 0));

    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();

    expect(window(tester).left, lessThanOrEqualTo(700 - metrics.dialogDragKeepVisible + 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('окно едет с первой же точки — порога у протяжки нет', (tester) async {
    await openDialog(tester);
    final before = window(tester);

    // Порог нужен там, где с протяжкой спорит щелчок; по заголовку щелчок не
    // значит ничего, и ждать восьми точек незачем.
    await drag(tester, title(), const Offset(3, 0));

    expect(window(tester).left - before.left, moreOrLessEquals(3, epsilon: 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('перетаскивание не трогает фокус и набранное', (tester) async {
    await openDialog(tester);
    await tester.enterText(dialogField(), '/home/docs');
    await tester.pumpAndSettle();

    await drag(tester, title(), const Offset(80, 40));

    expect(tester.widget<TextField>(dialogField()).controller?.text, '/home/docs');
    // Поле осталось в фокусе — и принимает ввод дальше.
    await tester.enterText(dialogField(), '/home');
    await tester.pumpAndSettle();
    expect(runtime.app.left.directory?.pathString, '/home');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('закрыли и открыли снова — окно на месте', (tester) async {
    await openDialog(tester);
    final home = window(tester);

    await drag(tester, title(), const Offset(200, 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    runtime.commands.run(
      OpenPathCommand.commandId,
      CommandInvocation(parameters: {OpenPathCommand.panelParam: OpenPathCommand.leftPanel}),
    );
    await tester.pumpAndSettle();

    // Смещение живёт, пока живёт окно: запоминать его между запусками нечему.
    expect(window(tester), home);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
  });
}
