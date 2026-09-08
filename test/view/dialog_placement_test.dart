import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Где встаёт окно, названное про панель, и какой оно ширины
/// (`docs/spec/dialog-placement.md`).
///
/// Окно приложения — 1200 точек, раздел пополам: левая панель `[0, 600]`,
/// правая `[600, 1200]`.
void main() {
  const double width = 1200;
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/docs')])..home = '/home',
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
  });

  Future<void> start(WidgetTester tester, {double appWidth = width}) async {
    tester.view.physicalSize = Size(appWidth, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  /// Само окно: рама занимает всю область, а окно — то, что внутри неё.
  Rect window(WidgetTester tester) =>
      tester.getRect(find.descendant(of: find.byType(DialogFrame), matching: find.byType(DialogWidth)));

  FcMetrics metrics(WidgetTester tester) => FcTheme.of(tester.element(find.byType(DialogFrame))).metrics;

  /// Окно с заведомо непомерным содержимым: ширину ему это не меняет — её
  /// назначает область, — но видно, что содержимое окно не растягивает.
  Future<void> showWide(WidgetTester tester, DialogArea area) async {
    runtime.app.view.showDialog(
      DialogSpec(title: 'Wide', area: area, ownWidth: true, content: const SizedBox(width: 5000, height: 100)),
    );
    await tester.pumpAndSettle();
  }

  /// Окно приложения поуже: при 900 точках панель ровно та, что окно «открыть
  /// путь» просило себе целиком, — раньше оно и ложилось от рамки до рамки.
  testWidgets('над тесной панелью окно не ложится от рамки до рамки', (tester) async {
    await start(tester, appWidth: 900);
    runtime.commands.run(
      OpenPathCommand.commandId,
      CommandInvocation(parameters: {OpenPathCommand.panelParam: OpenPathCommand.leftPanel}),
    );
    await tester.pumpAndSettle();

    final inset = metrics(tester).dialogAreaInset;
    final at = window(tester);
    expect(at.left, moreOrLessEquals(inset, epsilon: 0.5));
    expect(at.right, moreOrLessEquals(900 / 2 - inset, epsilon: 0.5));
  });

  testWidgets('ширину окна назначает панель, а не содержимое', (tester) async {
    await start(tester);
    // Два окна с разным содержимым над одной панелью: узкое и непомерное.
    // Ширина у них одна и та же — панель без полей.
    final shown = runtime.app.view.showDialog(
      const DialogSpec(title: 'Copy', area: DialogArea(end: 0.5), content: CommandDialogProgress(message: 'file')),
    );
    await tester.pumpAndSettle();
    final narrow = window(tester);

    runtime.app.view.closeDialog(shown);
    await tester.pumpAndSettle();
    await showWide(tester, const DialogArea(end: 0.5));
    final wide = window(tester);

    final inset = metrics(tester).dialogAreaInset;
    expect(narrow.width, moreOrLessEquals(width / 2 - inset * 2, epsilon: 0.5));
    expect(wide.width, moreOrLessEquals(narrow.width, epsilon: 0.5));
    expect(wide.left, moreOrLessEquals(inset, epsilon: 0.5));
  });

  testWidgets('над правой панелью всё зеркально', (tester) async {
    await start(tester);
    await showWide(tester, const DialogArea(start: 0.5));

    final inset = metrics(tester).dialogAreaInset;
    final at = window(tester);
    expect(at.left, moreOrLessEquals(width / 2 + inset, epsilon: 0.5));
    expect(at.right, moreOrLessEquals(width - inset, epsilon: 0.5));
  });

  testWidgets('окно во всё приложение ширину берёт по содержимому', (tester) async {
    await start(tester);
    await showWide(tester, DialogArea.window);

    // Области, от которой считать ширину, у такого окна нет: сколько запросило
    // содержимое, столько и вышло — вплоть до краёв приложения.
    final at = window(tester);
    expect(at.left, moreOrLessEquals(0, epsilon: 0.5));
    expect(at.right, moreOrLessEquals(width, epsilon: 0.5));
  });
}
