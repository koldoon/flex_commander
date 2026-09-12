import 'package:fc_panels/fc_panels.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Стрелки «назад» и «вперёд» в шапке панели
/// (`docs/spec/session-history.md`, §9).
void main() {
  late AppRuntime runtime;

  Future<void> open(WidgetTester tester) async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.directory('/home/pics'),
        FakeEntry.file('/home/notes.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();

    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  /// Цвет стрелки: живая набрана цветом пути, приглушённая — цветом
  /// неактивной плашки.
  Color colorOf(WidgetTester tester, IconData glyph) {
    final icons = tester.widgetList<Icon>(find.descendant(of: find.byType(HistoryArrows), matching: find.byType(Icon)));
    return icons.firstWhere((icon) => icon.icon == glyph).color!;
  }

  testWidgets('в начале пути обе стрелки приглушены', (tester) async {
    await open(tester);

    const colors = DefaultColors();
    final theme = FcTheme.of(tester.element(find.byType(HistoryArrows).first));
    expect(colorOf(tester, theme.icons.angleLeft), colors.pathInactiveText);
    expect(colorOf(tester, theme.icons.angleRight), colors.pathInactiveText);
  });

  testWidgets('прошли каталог — «назад» ожила, «вперёд» ещё нет', (tester) async {
    await open(tester);
    await runtime.app.left.openPath('/home/docs');
    await tester.pumpAndSettle();

    const colors = DefaultColors();
    final theme = FcTheme.of(tester.element(find.byType(HistoryArrows).first));
    expect(colorOf(tester, theme.icons.angleLeft), colors.pathText);
    expect(colorOf(tester, theme.icons.angleRight), colors.pathInactiveText);
  });

  testWidgets('нажатие на стрелку ведёт панель по её шагам', (tester) async {
    await open(tester);
    await runtime.app.left.openPath('/home/docs');
    await tester.pumpAndSettle();

    final theme = FcTheme.of(tester.element(find.byType(HistoryArrows).first));
    final back = find.descendant(
      of: find.byType(HistoryArrows).first,
      matching: find.byWidgetPredicate((widget) => widget is Icon && widget.icon == theme.icons.angleLeft),
    );
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(runtime.app.left.currentPath, '/home');
    expect(runtime.app.left.canGoForward, isTrue, reason: 'вперёд теперь есть куда');
  });

  testWidgets('длинный путь по-прежнему обрезается с головы, а не с хвоста', (tester) async {
    // Стрелки отняли у пути место, а плашка меряет его сама: не зная, сколько
    // у неё отняли, она отмеряла путь по всей ширине — и конец пути уходил за
    // край, обрезанный уже с хвоста (`docs/spec/session-history.md`, §9).
    await open(tester);
    tester.view.physicalSize = const Size(560, 600);
    await tester.pumpAndSettle();
    await runtime.app.left.openPath('/home/docs');
    await tester.pumpAndSettle();

    final plate = find.byType(FcPathPlate).first;
    final shown = (tester.widget(find.descendant(of: plate, matching: find.byType(Text)).first) as Text).data!;

    expect(shown, isNot(endsWith('…')), reason: 'обрезан хвост — конец пути потерян');
    if (shown.startsWith('…')) {
      expect('/home/docs', endsWith(shown.substring(1)));
    } else {
      expect(shown, '/home/docs', reason: 'путь поместился целиком — обрезать нечего');
    }
  });

  testWidgets('стрелки стоят слева от пути и не отнимают его целиком', (tester) async {
    await open(tester);
    await runtime.app.left.openPath('/home/docs');
    await tester.pumpAndSettle();

    final arrows = tester.getRect(find.byType(HistoryArrows).first);
    final path = tester.getRect(find.text('/home/docs').first);

    expect(arrows.right, lessThanOrEqualTo(path.left));
    expect(path.width, greaterThan(arrows.width), reason: 'путь — главное в плашке');
  });
}
