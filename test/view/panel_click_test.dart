import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Щелчок мышью в соседнюю панель: курсор и активность приходят вместе.
///
/// Панель зажигалась по **нажатию**, а курсор переставлялся по
/// **отпусканию**, — и между ними человек успевал увидеть курсор там, где тот
/// стоял в прошлый раз (`docs/spec/panel-views.md`, §9).
void main() {
  late AppRuntime runtime;

  Application app() => runtime.app;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/alpha.txt', size: 10),
        FakeEntry.file('/home/beta.txt', size: 10),
        FakeEntry.file('/home/gamma.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  /// Середина строки с таким именем — в правой панели.
  Offset rowCenter(WidgetTester tester, String name) {
    final table = find.byType(FileTable).at(1);
    final rect = tester.getRect(table);
    final metrics = FcTheme.of(tester.element(table)).metrics;
    final index = app().right.entries.indexWhere((entry) => entry.name == name);
    expect(index, isNonNegative, reason: 'в панели нет строки «$name»');
    return Offset(
      rect.left + rect.width / 2,
      rect.top + metrics.headerRowHeight + index * metrics.rowHeight + metrics.rowHeight / 2,
    );
  }

  testWidgets('щелчок в соседнюю панель не показывает курсор на старом месте', (tester) async {
    await pumpApp(tester);

    // Правая панель стоит на своей строке и не активна: клавиши у левой.
    app().right.setCursorIndex(app().right.entries.indexWhere((entry) => entry.name == 'gamma.txt'));
    await tester.pumpAndSettle();
    final was = app().right.cursorIndex;
    expect(app().right.active, isFalse, reason: 'стенд ни о чём, если правая и так активна');

    final target = app().right.entries.indexWhere((entry) => entry.name == 'alpha.txt');
    expect(target, isNot(was), reason: 'щёлкаем не туда, где курсор уже стоит');

    final gesture = await tester.startGesture(rowCenter(tester, 'alpha.txt'));
    // Кнопку держат: живьём это доли секунды, и ровно в них была видна беда.
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      app().right.active && app().right.cursorIndex == was,
      isFalse,
      reason: 'зажечься со старым курсором панель не должна',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(app().right.active, isTrue, reason: 'панель стала активной');
    expect(app().right.cursorIndex, target, reason: 'курсор там, куда щёлкнули');
  });
}
