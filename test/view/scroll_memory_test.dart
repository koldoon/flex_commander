import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вернулся в каталог — он стоит так же, как стоял, когда из него ушли
/// (`docs/spec/scroll-memory.md`).
///
/// Без памяти новый список получал «наименьшую прокрутку, при которой курсор
/// виден», и каталог, из которого вышли, вставал у нижнего края.
void main() {
  late AppController app;

  Future<void> pumpApp(WidgetTester tester, String? view) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/other'),
      for (var i = 0; i < 120; i++) ...[
        FakeEntry.directory('/dir-${i.toString().padLeft(3, '0')}'),
        FakeEntry.file('/dir-${i.toString().padLeft(3, '0')}/inside.txt', size: 1),
      ],
    ]);
    final settings = AppSettings(
      left: view == null ? PanelSettings.defaults('/') : PanelSettings(path: '/', view: view),
      right: PanelSettings.defaults('/other'),
    );
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Где на экране строка с этим именем — в списке левой панели.
  Rect rowOf(WidgetTester tester, String name) {
    final label = find.descendant(of: find.byType(Scrollable), matching: find.text(name));
    expect(label, findsWidgets, reason: 'строки $name на экране нет');
    return tester.getRect(label.first);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  for (final (title, view, down, up) in [
    ('таблица', null, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp),
    ('кратко', BriefView.viewId, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft),
    ('значки', IconsView.viewId, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp),
  ]) {
    testWidgets('$title: вышел наверх — каталог там же, где был', (tester) async {
      await pumpApp(tester, view);
      // Уехать далеко вниз, а потом вернуть курсор вверх: прокрутка стоит, и
      // курсор посреди экрана — не у края, куда его поставил бы расчёт.
      await press(tester, down, times: 30);
      await press(tester, up, times: 3);
      final name = app.left.currentEntry!.name;
      final before = rowOf(tester, name);

      await press(tester, LogicalKeyboardKey.enter);
      expect(app.left.currentPath, '/$name', reason: 'вошли в каталог');
      await app.left.goUp();
      await tester.pumpAndSettle();

      expect(app.left.currentEntry?.name, name, reason: 'курсор вернулся на каталог (Г11)');
      expect(rowOf(tester, name).topLeft, before.topLeft, reason: 'строка на том же месте экрана');
      expect(
        app.left.scrollOffset,
        app.left.rememberedScroll('/'),
        reason: 'сессия знает, где список встал: это переживёт перезапуск',
      );
    });
  }

  testWidgets('чужой вид не годится: ушли таблицей, вернулись значками — от курсора', (tester) async {
    await pumpApp(tester, null);
    await press(tester, LogicalKeyboardKey.arrowDown, times: 30);
    await press(tester, LogicalKeyboardKey.arrowUp, times: 3);
    final name = app.left.currentEntry!.name;

    await press(tester, LogicalKeyboardKey.enter);
    await app.left.setView(IconsView.viewId);
    await tester.pumpAndSettle();
    await app.left.goUp();
    await tester.pumpAndSettle();

    // Смещение таблицы для значков ничего не значит: курсор просто виден.
    final scrollable = find.byType(Scrollable).first;
    final row = rowOf(tester, name);
    expect(tester.getRect(scrollable).overlaps(row), isTrue, reason: 'курсор на экране');
  });
}
