import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Показ страниц: плашка, клавиши и то, что заказано у системы.
void main() {
  late FakeSystemPdf system;
  late PdfViewerScreen screen;

  Future<void> pump(WidgetTester tester) async {
    await tester.runAsync(() async {
      final disk = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/doc.pdf', content: '${pdfHeader}body'.codeUnits),
      ]);
      final node = (await disk.resolvePath().run('/home/doc.pdf'))!;
      final settings = PdfViewerSettings();
      screen = PdfViewerScreen(
        entry: entryValueOf(node),
        document: await PdfDocument.read(
          entryValueOf(node),
          NodeContent(node),
          settings,
          system: system,
          checkpoint: () async {},
        ),
        settings: settings,
        onSettingsChanged: () {},
      );
    });
    addTearDown(() => screen.close());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: SizedBox(width: 400, height: 300, child: PdfViewerView(screen: screen))),
      ),
    );
    await tester.pump();
  }

  /// Дождаться отрисовки: распаковка `png` идёт настоящим движком, вне
  /// поддельного времени.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  setUp(() => system = FakeSystemPdf(pages: List.filled(10, const Size(600, 800))));

  testWidgets('в плашке номер страницы и их число', (tester) async {
    await pump(tester);

    expect(find.textContaining('Page 1 of 10'), findsOneWidget);
  });

  testWidgets('рисуются видимые страницы и соседняя, а не весь документ', (tester) async {
    await pump(tester);
    await settle(tester);

    final pages = system.opened.single.rendered.map((r) => r.$1).toSet();
    expect(pages, containsAll([0, 1]));
    expect(pages.length, lessThanOrEqualTo(3));
    expect(screen.cache.imageOf(0), isNotNull);
  });

  testWidgets('End ведёт в конец, Home — в начало, и номер в плашке следом', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(screen.offset.dy, screen.maxOffset.dy);
    expect(find.textContaining('Page 10 of 10'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(screen.offset.dy, 0);
  });

  testWidgets('стрелка вправо доезжает до начала следующей страницы', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(screen.offset.dy, closeTo(screen.topOf(1), 0.5));
  });

  testWidgets('PgDn листает почти экраном', (tester) async {
    await pump(tester);
    final viewport = screen.viewport.height;

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();

    expect(screen.offset.dy, closeTo(viewport * 0.9, 0.5));
  });

  testWidgets('колесо листает, а не приближает', (tester) async {
    await pump(tester);
    final scale = screen.scale;

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(PdfViewerView))));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(screen.offset.dy, 120);
    expect(screen.scale, scale);
  });
}
