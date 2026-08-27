import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'images.dart';

/// Показ картинки: размер, прокрутка и то, что видно в плашке.
void main() {
  late InMemoryContentProvider disk;

  setUp(() {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/big.png', content: imageOf(bigPngData)),
      FakeEntry.file('/home/small.png', content: imageOf(pngData)),
    ]);
  });

  Future<ImageViewerScreen> screenOf(String name, {bool fitToWindow = true}) async {
    final node = (await disk.resolvePath().run('/home/$name'))!;
    final settings = ImageViewerSettings(fitToWindow: fitToWindow);
    final document = await ImageDocument.read(node, settings, checkpoint: () async {});
    return ImageViewerScreen(node: node, document: document, settings: settings, onSettingsChanged: () {});
  }

  /// Окно вдвое меньше картинки: на таком и видно разницу между «вписать» и
  /// «точка в точку».
  Future<void> pump(WidgetTester tester, ImageViewerScreen screen) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: SizedBox(width: 200, height: 200, child: ImageViewerView(screen: screen))),
      ),
    );
    await tester.pump();
  }

  testWidgets('«точка в точку» показывает картинку своего размера, а не по окну', (tester) async {
    final screen = await screenOf('big.png', fitToWindow: false);
    await pump(tester, screen);

    // Ровно то, что поймала живая проверка: картинка крупнее окна ужималась в
    // него — «точка в точку» превращалась в то же «вписать».
    final size = tester.getSize(find.byType(Image));
    expect(size.width, 400);
    expect(size.height, 300);
  });

  testWidgets('«вписать» уменьшает крупную, но не растягивает мелкую', (tester) async {
    await pump(tester, await screenOf('big.png'));
    final fitted = tester.getSize(find.byType(Image));

    // Вписана целиком: по большей стороне — ровно в окно (за вычетом рамы).
    expect(fitted.width, lessThanOrEqualTo(200));
    expect(fitted.width / fitted.height, closeTo(400 / 300, 0.01));

    await pump(tester, await screenOf('small.png'));

    // Мелкая осталась собой: иконка в шесть точек не должна занимать экран.
    expect(tester.getSize(find.byType(Image)).width, 6);
  });

  testWidgets('в плашке — размеры, формат и объём', (tester) async {
    await pump(tester, await screenOf('big.png'));

    final plate = tester.widget<FcPathPlate>(find.byType(FcPathPlate));
    expect(plate.trailing, contains('400×300'));
    expect(plate.trailing, contains('PNG'));
  });

  group('прокрутка', () {
    test('не влезающая картинка возится, но не дальше краёв', () async {
      final screen = await screenOf('big.png', fitToWindow: false);
      const viewport = Size(200, 200);
      const shown = Size(400, 300);

      screen.moveBy(const Offset(1000, 1000), shown: shown, viewport: viewport);

      // Дальше половины разницы уезжать некуда: иначе картинку можно утащить в
      // пустоту и потерять из виду.
      expect(screen.offset, const Offset(100, 50));
    });

    test('влезающую возить некуда', () async {
      final screen = await screenOf('small.png', fitToWindow: false);

      screen.moveBy(const Offset(50, 50), shown: const Size(6, 4), viewport: const Size(200, 200));

      expect(screen.offset, Offset.zero);
    });
  });
}
