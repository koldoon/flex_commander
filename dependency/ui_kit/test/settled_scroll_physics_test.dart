import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Длинный список, прокрученный вниз, становится коротким, а прыжок к началу
  /// делается ещё по меркам длинного — так вид входит в маленький каталог.
  Future<ScrollPosition> shrink(WidgetTester tester, ScrollPhysics? physics) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget list(int count) => Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        controller: controller,
        physics: physics,
        itemExtent: 20,
        itemCount: count,
        itemBuilder: (context, index) => Text('$index'),
      ),
    );

    await tester.pumpWidget(list(100));
    controller.jumpTo(1000);
    await tester.pump();

    controller.jumpTo(16);
    await tester.pumpWidget(list(3));
    return controller.position;
  }

  /// Пружина — физика macOS; на других платформах прокрутка и так упирается.
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('стандартная физика macOS отпружинивает непрошенно', variant: macOS, (tester) async {
    final position = await shrink(tester, null);
    await tester.pump(const Duration(milliseconds: 50));
    expect(position.pixels, greaterThan(0), reason: 'стенд воспроизводит беду, иначе он ничего не сторожит');
    await tester.pumpAndSettle();
  });

  testWidgets('без жеста прокрутка сразу встаёт в пределы, а не пружинит', variant: macOS, (tester) async {
    final position = await shrink(tester, const SettledScrollPhysics());
    expect(position.pixels, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(position.pixels, 0);
  });
}
