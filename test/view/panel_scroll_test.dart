import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Содержимое во весь экран — то же, чем встают редактор и просмотрщик: панели
/// оно прячет, а не закрывает.
class _FullScreen extends ChangeNotifier implements ViewportState {
  @override
  bool get takesKeyboard => true;

  @override
  void close() {}
}

/// Модуль, объявляющий, чем это содержимое рисуется.
class _FullScreenModule implements FcFrontendModule {
  const _FullScreenModule();

  @override
  String get id => 'test.fullscreen';

  @override
  String get title => 'Full screen stub';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.view<_FullScreen>((context, state) => const ColoredBox(color: Color(0xFF000000)));
  }
}

/// Прокрутка панели переживает полноэкранный вид
/// (`docs/spec/panel-views.md`, §10).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        for (var i = 0; i < 120; i++) FakeEntry.file('/home/file-${i.toString().padLeft(3, '0')}.txt', size: 10),
      ])..home = '/home',
      modules: [...featureModules(), const _FullScreenModule()],
    );
    await runtime.app.start();
  });

  /// Прокрутка списка левой панели.
  double offsetOf(WidgetTester tester) =>
      tester
          .widget<ListView>(find.descendant(of: find.byType(FileTable).first, matching: find.byType(ListView)))
          .controller!
          .offset;

  testWidgets('курсор остаётся там, где его оставили', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    // Уводим курсор далеко вниз: список прокручивается за ним.
    for (var i = 0; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();

    final scrolled = offsetOf(tester);
    expect(scrolled, greaterThan(0), reason: 'список не прокрутился — проверять нечего');
    final cursorRow = tester.getRect(find.text(runtime.app.left.currentEntry!.name).first);

    // Полноэкранный вид и обратно — как у просмотрщика и редактора.
    runtime.app.view.pushViewportContent(ViewportPosition.fullscreen, _FullScreen());
    await tester.pumpAndSettle();
    runtime.app.view.popViewportContent(ViewportPosition.fullscreen);
    await tester.pumpAndSettle();

    // Список встаёт туда, где стоял: раньше он подматывался к курсору заново,
    // и тот оказывался у нижнего края — не там, где его оставили.
    expect(offsetOf(tester), scrolled);
    expect(tester.getRect(find.text(runtime.app.left.currentEntry!.name).first).top, closeTo(cursorRow.top, 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });
}
