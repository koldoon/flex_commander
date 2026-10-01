import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дочерние окна — поверх, а не вместо (`docs/spec/child-dialogs.md`).
void main() {
  late AppRuntime runtime;
  late InMemoryTreeProvider provider;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.txt', size: 4),
      FakeEntry.directory('/work'),
      FakeEntry.file('/work/a.txt', size: 9),
    ])..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/work')),
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

  /// Окно на экране — рамка, в которой стоит этот текст.
  Rect windowOf(WidgetTester tester, String text) {
    final frame = find.ancestor(of: find.text(text).first, matching: find.byType(DialogFrame)).first;
    final window = find.descendant(of: frame, matching: find.byType(FocusScope)).first;
    return tester.getRect(window);
  }

  Future<void> openNewPreset(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FcButton, 'New').first);
    await tester.pumpAndSettle();
  }

  testWidgets('подтверждение из настроек встаёт по центру настроек', (tester) async {
    await pumpApp(tester);
    await openNewPreset(tester);

    final dialogs = runtime.app.view.openDialogs;
    expect(dialogs, hasLength(2));
    expect(dialogs.last.spec.parent, dialogs.first.id, reason: 'родитель — окно, кнопкой которого подняли');

    final parent = windowOf(tester, 'Presets');
    final child = windowOf(tester, 'New set');
    expect((child.center.dx - parent.center.dx).abs(), lessThan(1.5));
    expect((child.center.dy - parent.center.dy).abs(), lessThan(1.5));
  });

  testWidgets('Esc закрывает дочернее, а следующий — уже родителя', (tester) async {
    await pumpApp(tester);
    await openNewPreset(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(runtime.app.view.dialogs, hasLength(1), reason: 'настройки остались');

    // Фокус вернулся родителю: его Esc доходит до него.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(runtime.app.view.dialogs, isEmpty);
  });

  testWidgets('закрыли родителя — ушло и дочернее', (tester) async {
    await pumpApp(tester);
    await openNewPreset(tester);

    runtime.app.view.closeDialog(runtime.app.view.openDialogs.first.id);
    await tester.pumpAndSettle();

    expect(runtime.app.view.dialogs, isEmpty);
  });

  testWidgets('вопрос посреди копирования встаёт поверх окна работы', (tester) async {
    await pumpApp(tester);
    runtime.app.left.setCursorToName('a.txt');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();

    final dialogs = runtime.app.view.openDialogs;
    expect(dialogs, hasLength(2), reason: 'окно работы и над ним вопрос');
    expect(dialogs.last.spec.content, isA<CommandDialogQuestion>());
    expect(dialogs.last.spec.parent, dialogs.first.id);
    expect(find.byType(CommandDialogQuestion), findsOneWidget);
    expect(find.byType(CommandDialogForm), findsNothing, reason: 'вопрос не подменяет окно работы формой');

    // Ответили — вопрос ушёл, работа доиграла и закрыла своё окно.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(runtime.app.view.dialogs, isEmpty);
  });
}
