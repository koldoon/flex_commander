import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Длинное имя договаривается подсказкой (`docs/spec/tooltips.md`).
void main() {
  const long = 'невероятно длинное имя файла, которому не хватит никакой ширины.txt';
  const short = 'a.txt';

  /// Что от имени видно в колонке: расширение показывает соседняя `Ext`,
  /// поэтому договаривается ровно то, что набрано в ячейке.
  const shownLong = 'невероятно длинное имя файла, которому не хватит никакой ширины';
  const medium = 'середина.txt';
  const shownMedium = 'середина';

  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.file('/home/$long', size: 10),
    FakeEntry.file('/home/$short', size: 20),
    FakeEntry.file('/home/$medium', size: 40),
    FakeEntry.directory('/home/sub'),
    FakeEntry.file('/home/sub/deep.txt', size: 30),
  ])..home = '/home';

  Future<AppRuntime> open(WidgetTester tester, {Size size = const Size(900, 400), String? view}) async {
    final runtime = await testApp(provider: provider(), modules: featureModules());
    await runtime.app.start();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    if (view != null) {
      await runtime.app.left.setView(view);
      await tester.pumpAndSettle();
    }
    return runtime;
  }

  /// Подсказка у этого текста; пусто — её нет.
  Finder tipOf(String text) => find.ancestor(of: find.text(text).first, matching: find.byType(FcTooltip));

  testWidgets('длинное имя договаривается подсказкой, короткое — молчит', (tester) async {
    await open(tester);

    expect(tester.widget<FcTooltip>(tipOf(shownLong).first).message, shownLong);
    expect(tipOf('a'), findsNothing, reason: 'подсказка, повторяющая видимое, только мешает читать список');

    await disposeScreen(tester);
  });

  testWidgets('сузили колонку — подсказка завелась, расширили — ушла', (tester) async {
    await open(tester);

    // Имя, которое поначалу помещается целиком.
    expect(tipOf(shownMedium), findsNothing);

    // Граница — левый край колонки справа от имени; влево она эту колонку
    // расширяет, и «резиновому» имени остаётся меньше.
    final grip = find.byWidgetPredicate(
      (widget) => widget is MouseRegion && widget.cursor == SystemMouseCursors.resizeColumn,
    );
    final at = tester.getCenter(grip.first);

    await tester.dragFrom(at, const Offset(-220, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(tipOf(shownMedium), findsOneWidget, reason: 'теперь не помещается');

    await tester.dragFrom(tester.getCenter(grip.first), const Offset(220, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(tipOf(shownMedium), findsNothing, reason: 'снова помещается — договаривать нечего');

    await disposeScreen(tester);
  });

  testWidgets('заголовок колонки договаривается полным названием', (tester) async {
    await open(tester, size: const Size(620, 400));

    // Колонку сузили так, что название в ней не помещается.
    final grip = find.byWidgetPredicate(
      (widget) => widget is MouseRegion && widget.cursor == SystemMouseCursors.resizeColumn,
    );
    await tester.dragFrom(tester.getCenter(grip.at(1)), const Offset(90, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(tipOf('Size'), findsOneWidget, reason: 'обрубленное посреди буквы — тем более загадка');

    await disposeScreen(tester);
  });

  testWidgets('строка состояния договаривает то, что в ней не поместилось', (tester) async {
    final runtime = await open(tester, size: const Size(620, 400));

    // Курсор на длинном имени: сюда и смотрят, когда имя в списке обрезано.
    runtime.app.left.setCursorToName(long);
    await tester.pumpAndSettle();

    final status = find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(FcTooltip));
    expect(tester.widget<FcTooltip>(status).message, long);

    // Короткое имя полосу не переполняет — и молчит.
    runtime.app.left.setCursorToName(short);
    await tester.pumpAndSettle();
    expect(status, findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('дерево: имя ветви договаривается, а размер молчит', (tester) async {
    await open(tester, view: TreeView.viewId);

    expect(tester.widget<FcTooltip>(tipOf(long).first).message, long);
    // Число не режется: колонка размера своей ширины, и в ней всё помещается.
    expect(tipOf('40'), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('краткий вид: имя договаривается тем же', (tester) async {
    await open(tester, view: BriefView.viewId);

    // В кратком виде колонки `Ext` нет — имя показано целиком, и целиком же
    // договаривается.
    expect(tester.widget<FcTooltip>(tipOf(long).first).message, long);
    expect(tipOf(short), findsNothing);

    await disposeScreen(tester);
  });
}
