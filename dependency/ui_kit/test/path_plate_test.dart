import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Плашка пути обрезает **сама**, значит и мерить обязана тем, чем рисует.
void main() {
  const metrics = DefaultMetrics();
  const path = '/Users/koldoon/Library/Application Support/AIR/Volumes/Data/Applications/AIRSDKManager.app';

  /// Окружение материальное и со своей разрядкой — как в живом приложении:
  /// `Text` со стилем-наследником подмешивает её к нашему стилю.
  Future<void> pumpPlate(WidgetTester tester, {required double width, double letterSpacing = 2}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: TextTheme(bodyMedium: TextStyle(letterSpacing: letterSpacing)),
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 300,
              child: const FcPanelFrame(header: FcPathPlate(path: path), child: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('длинный путь не вылезает за плашку', (tester) async {
    await pumpPlate(tester, width: 393);

    final plate = tester.getRect(find.byType(FcPathPlate));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text)),
    );

    // Ширина **набранной** строки, а не коробки: вылезший текст обрезается по
    // коробке, и по ней беда не видна. Помещается — значит помещается вместе с
    // полями плашки и её обводкой.
    final inner = plate.width - 2 * (metrics.labelPadding + metrics.strokeWidth);
    expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(inner + 0.01));
  });

  testWidgets('обрезается голова, а не хвост: текущий каталог виден целиком', (tester) async {
    await pumpPlate(tester, width: 393);

    final shown =
        (tester.widget(find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text))) as Text).data!;
    expect(shown, startsWith('…'));
    expect(path, endsWith(shown.substring(1)));
  });

  testWidgets('короткому пути многоточие ни к чему', (tester) async {
    await pumpPlate(tester, width: 393);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 393,
              height: 300,
              child: FcPanelFrame(header: FcPathPlate(path: '/home'), child: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('/home'), findsOneWidget);
  });
}
