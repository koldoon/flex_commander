import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Выделение текста на страницах (`docs/spec/pdf-viewer.md`, §17).
void main() {
  group('жесты', () {
    late FakeSystemPdf system;
    late PdfViewerScreen screen;

    FakePdfDocument handle() => system.opened.single;

    Future<void> pump(WidgetTester tester) async {
      system = FakeSystemPdf(pages: List.filled(10, const Size(600, 800)));
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

    /// Точка на первой странице, в долях её сторон. Начало обзора совпадает
    /// с началом рамы: страницам отдана вся рама (`fillsFrame`).
    Offset onPage(WidgetTester tester, double x, double y) {
      final frame = tester.getRect(find.byType(ClipRect).first);
      final page = screen.pageRects[0];
      return Offset(frame.left + page.left + page.width * x, frame.top + page.top + page.height * y);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('мышью по странице — выделение, а не ход документа', (tester) async {
      await pump(tester);

      final gesture = await tester.startGesture(onPage(tester, 0.2, 0.2), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(40, 20));
      await gesture.up();
      await settle(tester);

      expect(screen.offset, Offset.zero, reason: 'документ не поехал');
      expect(screen.hasSelection, isTrue);
      expect(handle().selects.last.$3, PdfSelectionUnit.character);
      expect(handle().selects.last.$2?.page, 0);
    });

    testWidgets('мышью по полю — ход документа, как раньше', (tester) async {
      await pump(tester);
      final frame = tester.getRect(find.byType(ClipRect).first);

      // Левое поле: страница начинается в двенадцати точках от края.
      final gesture = await tester.startGesture(frame.topLeft + const Offset(4, 150), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -40));
      await gesture.up();
      await settle(tester);

      expect(screen.offset.dy, greaterThan(0));
      expect(screen.hasSelection, isFalse);
      expect(handle().selects, isEmpty);
    });

    testWidgets('трекпад по странице прокручивает, а не выделяет', (tester) async {
      await pump(tester);
      final at = onPage(tester, 0.3, 0.3);

      final pointer = TestPointer(2, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pointer.panZoomStart(at));
      for (var i = 1; i <= 4; i++) {
        await tester.sendEventToBinding(
          pointer.panZoomUpdate(at, pan: Offset(0, -20.0 * i), timeStamp: Duration(milliseconds: 100 * i)),
        );
      }
      await tester.sendEventToBinding(pointer.panZoomEnd(timeStamp: const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();

      expect(screen.offset.dy, greaterThan(0));
      expect(handle().selects, isEmpty);
    });

    testWidgets('двойной щелчок — слово, тройной — строка, одиночный — снимает', (tester) async {
      await pump(tester);
      final at = onPage(tester, 0.3, 0.3);

      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await settle(tester);
      expect(handle().selects.last.$3, PdfSelectionUnit.word);
      expect(screen.hasSelection, isTrue);

      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await settle(tester);
      expect(handle().selects.last.$3, PdfSelectionUnit.line);

      // Пауза дольше двойного щелчка — следующий снова одиночный.
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await settle(tester);
      expect(screen.hasSelection, isFalse);
    });

    testWidgets('вопросы раннеру не копятся: пока считает один, спрашивается последнее', (tester) async {
      await pump(tester);
      system.opened.single.holdSelects = true;

      final gesture = await tester.startGesture(onPage(tester, 0.1, 0.1), kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(10, 3));
      }
      expect(handle().selects, hasLength(1), reason: 'первый ещё считается');
      expect(screen.selectionRequests, 1);

      handle().releaseSelect();
      await tester.pump();
      expect(handle().selects, hasLength(2), reason: 'промежуточные пропущены, спрошено последнее');

      handle().releaseSelect();
      await gesture.up();
      await settle(tester);
      expect(handle().selects, hasLength(2));
    });

    testWidgets('мышь за нижним краем — документ крутится сам', (tester) async {
      await pump(tester);
      final frame = tester.getRect(find.byType(ClipRect).first);

      final gesture = await tester.startGesture(onPage(tester, 0.2, 0.2), kind: PointerDeviceKind.mouse);
      await gesture.moveTo(Offset(frame.left + 100, frame.bottom + 40));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final scrolled = screen.offset.dy;
      expect(scrolled, greaterThan(50));

      await gesture.up();
      await settle(tester);
      expect(screen.offset.dy, scrolled, reason: 'отпустили — встал');
    });
  });

  group('Cmd-C', () {
    test('копирует выделенное и говорит сколько; без выделения недоступна', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final clipboard = FakeClipboard();
      final system = FakeSystemPdf();
      final runtime = await testApp(
        provider: InMemoryContentProvider([
          FakeEntry.directory('/home'),
          FakeEntry.file('/home/doc.pdf', content: '${pdfHeader}one'.codeUnits),
        ])..home = '/home',
        clipboard: clipboard,
        modules: [...featureModules(), FakeSystemPdfModule(system)],
      );
      await runtime.app.start();
      runtime.app.left.setCursorToName('doc.pdf');
      await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
      await pumpEventQueue();
      final screen = runtime.app.view.contentAt(ViewportPosition.fullscreen)! as PdfViewerScreen;
      screen.layoutIn(const Size(632, 500));

      final copy = runtime.commands.find(CopyPdfSelectionCommand.commandId)!;
      expect(runtime.commands.isExecutable(copy), isFalse);

      screen.startSelection(const Offset(100, 100), unit: PdfSelectionUnit.word);
      await pumpEventQueue();
      expect(runtime.commands.isExecutable(copy), isTrue);

      expect(runtime.commands.dispatch(KeyCombination.parse('Cmd-C')), isTrue);
      await pumpEventQueue();

      expect(clipboard.text, 'word:0-0');
      expect(runtime.app.toasts.current?.message, contains('Copied'));
    });
  });
}
