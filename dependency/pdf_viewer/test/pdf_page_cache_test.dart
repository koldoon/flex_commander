import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Что заказано, что нарисовано и что отпущено.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePdfDocument handle;
  late PdfPageCache cache;

  setUp(() async {
    final system = FakeSystemPdf(pages: List.filled(5, const Size(600, 800)));
    final disk = InMemoryContentProvider([FakeEntry.file('/doc.pdf', content: '${pdfHeader}x'.codeUnits)]);
    final node = (await disk.resolvePath().run('/doc.pdf'))!;
    final document = await PdfDocument.read(
      entryValueOf(node),
      NodeContent(node),
      PdfViewerSettings(),
      system: system,
      checkpoint: () async {},
    );
    handle = system.opened.single;
    cache = PdfPageCache(document);
  });

  tearDown(() => cache.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('ширина — вверх до шага и не больше предела точек', () {
    expect(cache.widthFor(0, 300), 512);
    expect(cache.widthFor(0, 100000), cache.maxWidthOf(0));
    expect(cache.maxWidthOf(0) * cache.maxWidthOf(0) * 800 / 600, lessThanOrEqualTo(PdfPageCache.maxPixels));
  });

  test('рисует заказанное и не заказывает его снова', () async {
    cache.want({0: 512, 1: 512});
    await settle();

    expect(cache.imageOf(0), isNotNull);
    expect(cache.imageOf(1), isNotNull);

    // Тот же заказ — работы нет, хотя система вернула картинку меньше.
    cache.want({0: 512, 1: 512});
    await settle();
    expect(handle.rendered, hasLength(2));
  });

  test('крупнее — дорисовывает, а прежнее показывает до тех пор', () async {
    cache.want({0: 512});
    await settle();
    final small = cache.imageOf(0);

    cache.want({0: 1024});
    expect(cache.imageOf(0), same(small), reason: 'страница не гаснет при масштабе');
    await settle();

    expect(handle.rendered.last, (0, 1024));
  });

  test('ушедшее из заказа отпускается', () async {
    cache.want({0: 512, 1: 512});
    await settle();

    cache.want({1: 512});

    expect(cache.imageOf(0), isNull);
    expect(cache.imageOf(1), isNotNull);
  });

  test('не больше двух отрисовок разом', () async {
    cache.want({0: 512, 1: 512, 2: 512, 3: 512});
    expect(handle.rendered, hasLength(2));
    await settle();
    expect(handle.rendered, hasLength(4));
  });
}
