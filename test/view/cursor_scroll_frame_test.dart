import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Прокрутка за курсором — в том же кадре, что и сам курсор (`docs/widgets.md`,
/// раздел о списке).
///
/// Живой дефект: у края списка курсор мерцал. В кадре со сменой курсора новая
/// строка лежала за краем и даже не строилась, а прокрутка приходила кадром
/// позже. Поэтому проверка — после **одного** кадра на нажатие, а не после
/// `pumpAndSettle`: тот дождался бы прокрутки и ничего бы не увидел.
void main() {
  late AppController app;

  Future<void> pumpApp(WidgetTester tester, String? view) async {
    final provider = InMemoryTreeProvider([
      // Длинный список — в корне: в столбцах курсор стоит в корневом столбце,
      // и ходить стрелкой ему надо по нему.
      FakeEntry.directory('/other'),
      for (var i = 0; i < 120; i++) FakeEntry.directory('/dir-${i.toString().padLeft(3, '0')}'),
    ]);
    final settings = AppSettings(
      left: view == null ? PanelSettings.defaults('/') : PanelSettings(path: '/', view: view),
      // Правая панель — в другом каталоге: те же имена в ней путали бы поиск
      // строки под курсором.
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

  /// Строка под курсором построена и целиком в видимой части своего списка.
  void expectCursorOnScreen(WidgetTester tester, int step) {
    final name = app.left.currentEntry!.name;
    // Только в списке: в столбцах то же имя стоит ещё и в полосе пути.
    final label = find.descendant(of: find.byType(Scrollable), matching: find.text(name));
    expect(label, findsWidgets, reason: 'шаг $step: строки под курсором ($name) в этом кадре нет вовсе');
    final scrollable = find.ancestor(of: label.first, matching: find.byType(Scrollable)).first;
    final viewport = tester.getRect(scrollable);
    final row = tester.getRect(label.first);
    expect(
      viewport.contains(row.topLeft) && viewport.contains(row.bottomRight.translate(-1, -1)),
      isTrue,
      reason: 'шаг $step: строка под курсором ($name) за краем списка — $row вне $viewport',
    );
  }

  for (final (title, view, key) in [
    ('таблица', null, LogicalKeyboardKey.arrowDown),
    ('кратко', BriefView.viewId, LogicalKeyboardKey.arrowDown),
    ('значки', IconsView.viewId, LogicalKeyboardKey.arrowDown),
    ('дерево', TreeView.viewId, LogicalKeyboardKey.arrowDown),
    ('столбцы', ColumnsView.viewId, LogicalKeyboardKey.arrowDown),
  ]) {
    testWidgets('$title: у края курсор не пропадает ни на кадр', (tester) async {
      await pumpApp(tester, view);
      for (var step = 0; step < 80; step++) {
        await tester.sendKeyEvent(key);
        await tester.pump();
        expectCursorOnScreen(tester, step);
      }
      await tester.pumpAndSettle();
    });
  }
}
