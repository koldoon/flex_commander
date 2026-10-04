import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вид «Сжатое дерево» (`docs/spec/panel-view-compact-tree.md`).
void main() {
  Future<AppRuntime> open(WidgetTester tester, {double width = 900, String deep = 'acme'}) async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/src'),
      FakeEntry.directory('/home/src/main'),
      FakeEntry.directory('/home/src/main/java'),
      FakeEntry.directory('/home/src/main/java/$deep'),
      FakeEntry.file('/home/src/main/java/$deep/App.java', size: 1),
      FakeEntry.file('/home/src/main/java/$deep/Util.java', size: 1),
      FakeEntry.file('/home/readme.md', size: 1),
    ])..home = '/home';
    final runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();

    tester.view.physicalSize = Size(width, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(CompactTreeView.viewId);
    await tester.pumpAndSettle();
    runtime.app.left.setExpanded('/home/src', expanded: true);
    await tester.pumpAndSettle();
    return runtime;
  }

  Finder chain() => find.descendant(of: find.byType(CompactTreeView).first, matching: find.byType(FcChainName));

  testWidgets('вид просит свои строки и рисует цепочку одной строкой', (tester) async {
    final runtime = await open(tester);

    expect(runtime.app.left.rows, RowsKind.compactTree);
    expect(chain(), findsOneWidget);
    final name = tester.widget<FcChainName>(chain());
    expect(name.head, 'src/main/java');
    expect(name.name, 'acme');

    await disposeScreen(tester);
  });

  testWidgets('голова приглушена, имя — цветом строки', (tester) async {
    await open(tester);

    final name = tester.widget<FcChainName>(chain());
    expect(name.headStyle.color, isNot(name.style.color));

    await disposeScreen(tester);
  });

  testWidgets('подсказки нет, пока подпись влезает', (tester) async {
    await open(tester);

    expect(find.descendant(of: chain(), matching: find.byType(FcTooltip)), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('не влезла — голова режется, а подсказка договаривает', (tester) async {
    await open(tester, width: 640, deep: 'an-exceptionally-long-package-name-that-cannot-fit');

    // Какая ступень сработала, зависит от ширины; важно, что подпись
    // обрезана, а не вылезла за край, и что целиком её договаривает подсказка.
    final shown = tester.widget<RichText>(find.descendant(of: chain(), matching: find.byType(RichText)));
    expect(shown.text.toPlainText(), isNot('src/main/java/an-exceptionally-long-package-name-that-cannot-fit'));
    expect(find.descendant(of: chain(), matching: find.byType(FcTooltip)), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('шеврон строки цепочки сворачивает самый глубокий каталог', (tester) async {
    final runtime = await open(tester);
    final before = runtime.app.left.entries.length;

    final icons = FcTheme.of(tester.element(find.byType(CompactTreeView).first)).icons;
    final opened = String.fromCharCode(icons.branchOpen.codePoint);
    final row = find.ancestor(of: chain(), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.text(opened)));
    await tester.pumpAndSettle();

    expect(runtime.app.left.entries.length, before - 2, reason: 'App.java и Util.java ушли');
    expect(chain(), findsOneWidget, reason: 'строка осталась одна — свёрнут только acme');

    await disposeScreen(tester);
  });
}
