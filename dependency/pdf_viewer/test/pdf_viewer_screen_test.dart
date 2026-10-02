import 'dart:ui';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Чтение, отказы и раскладка страниц — без виджетов.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryContentProvider disk;

  setUp(() {
    disk = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/doc.pdf', content: '${pdfHeader}body'.codeUnits),
      FakeEntry.file('/home/fake.pdf', content: 'not a pdf at all'.codeUnits),
    ]);
  });

  Future<PdfDocument> read(
    String name, {
    SystemPdf? system,
    PdfViewerSettings? settings,
    Future<void> Function()? checkpoint,
  }) async {
    final node = (await disk.resolvePath().run('/home/$name'))!;
    return PdfDocument.read(
      entryValueOf(node),
      NodeContent(node),
      settings ?? PdfViewerSettings(),
      system: system,
      checkpoint: checkpoint ?? () async {},
    );
  }

  Future<PdfViewerScreen> screenOf(FakeSystemPdf system, {Size viewport = const Size(632, 500)}) async {
    final node = (await disk.resolvePath().run('/home/doc.pdf'))!;
    final screen = PdfViewerScreen(
      entry: entryValueOf(node),
      document: await read('doc.pdf', system: system),
      settings: PdfViewerSettings(),
      onSettingsChanged: () {},
    );
    screen.layoutIn(viewport);
    return screen;
  }

  group('отказы', () {
    test('без службы — отказ словами, а не байты текстовым', () async {
      await expectLater(
        read('doc.pdf'),
        throwsA(isA<ViewerRefused>().having((e) => e.reason, 'reason', contains('Cmd-O'))),
      );
    });

    test('больше предела — отказ, и система даже не спрошена', () async {
      final system = FakeSystemPdf();
      await expectLater(
        read('doc.pdf', system: system, settings: PdfViewerSettings(maxFileSize: 4)),
        throwsA(isA<ViewerRefused>().having((e) => e.reason, 'reason', contains('too large'))),
      );
      expect(system.opened, isEmpty);
    });

    test('не разобрала система — отказ «не PDF»', () async {
      await expectLater(
        read('fake.pdf', system: FakeSystemPdf()),
        throwsA(isA<ViewerRefused>().having((e) => e.reason, 'reason', contains('Not a PDF'))),
      );
    });

    test('заперт паролем — отказ, и документ в системе отпущен', () async {
      final system = FakeSystemPdf(locked: true);
      await expectLater(
        read('doc.pdf', system: system),
        throwsA(isA<ViewerRefused>().having((e) => e.reason, 'reason', contains('password'))),
      );
      expect(system.opened.single.closed, isTrue);
    });

    test('курсор ушёл, пока система разбирала, — документ отпущен', () async {
      final system = FakeSystemPdf();
      var calls = 0;
      await expectLater(
        read(
          'doc.pdf',
          system: system,
          // Последняя проверка — после разбора: её и роняем.
          checkpoint: () async {
            if (system.opened.isNotEmpty && ++calls == 1) {
              throw const OperationCanceled();
            }
          },
        ),
        throwsA(isA<OperationCanceled>()),
      );
      expect(system.opened.single.closed, isTrue);
    });
  });

  group('раскладка', () {
    test('по ширине: самая широкая страница — во всю ширину окна за вычетом полей', () async {
      final screen = await screenOf(FakeSystemPdf());

      // Окно 632, поля по 12 — самой широкой (800 пунктов) остаётся 608.
      expect(screen.scale, closeTo(608 / 800, 1e-9));
      final rects = screen.pageRects;
      expect(rects[2].width, closeTo(608, 1e-9));
      expect(rects[0].width, closeTo(600 * 608 / 800, 1e-9));
      expect(rects[0].center.dx, closeTo(316, 1e-9), reason: 'узкая страница — посередине');
      expect(rects[1].top, closeTo(rects[0].bottom + PdfViewerScreen.gap, 1e-9));
    });

    test('страница целиком помещается в окно по высоте', () async {
      final screen = await screenOf(FakeSystemPdf());
      screen.toggleFit();

      expect(screen.wholePage, isTrue);
      expect(screen.pageRects[0].height, lessThanOrEqualTo(500 - 2 * PdfViewerScreen.margin + 1e-9));
    });

    test('номер страницы — та, что в середине окна', () async {
      final screen = await screenOf(FakeSystemPdf());
      expect(screen.currentPage, 0);

      screen.scrollTo(Offset(0, screen.pageRects[1].top));
      expect(screen.currentPage, 1);

      screen.scrollTo(Offset(0, screen.maxOffset.dy));
      expect(screen.currentPage, 2);
    });

    test('прокрутка не уходит за края', () async {
      final screen = await screenOf(FakeSystemPdf());
      screen.scrollBy(const Offset(-100, -100));
      expect(screen.offset, Offset.zero);

      screen.scrollBy(const Offset(0, 1e9));
      expect(screen.offset.dy, screen.maxOffset.dy);
      expect(screen.offset.dx, 0, reason: 'по ширине вбок ехать некуда');
    });

    test('шаг страницей ведёт к началу следующей и назад — к началу текущей', () async {
      final screen = await screenOf(FakeSystemPdf());

      final second = screen.pageStepFrom(0, forward: true);
      expect(second, screen.topOf(1));

      final middle = screen.topOf(1) + 100;
      expect(screen.pageStepFrom(middle, forward: false), screen.topOf(1));
      expect(screen.pageStepFrom(screen.topOf(1), forward: false), 0);
    });

    test('масштаб держит место чтения', () async {
      final screen = await screenOf(FakeSystemPdf());
      final rects = screen.pageRects;
      // Стоим на трети второй страницы.
      screen.scrollTo(Offset(0, rects[1].top + rects[1].height / 3));

      screen.zoomBy(PdfViewerScreen.zoomStep);

      final after = screen.pageRects[1];
      expect(screen.offset.dy, closeTo(after.top + after.height / 3, 1e-6));
      expect(screen.offset.dx, greaterThan(0), reason: 'приблизили — середина осталась серединой');
    });

    test('смена размера окна держит место чтения', () async {
      final screen = await screenOf(FakeSystemPdf());
      final before = screen.pageRects[1];
      screen.scrollTo(Offset(0, before.top + before.height / 4));

      screen.layoutIn(const Size(400, 500));

      final after = screen.pageRects[1];
      expect(after.height, lessThan(before.height));
      expect(screen.offset.dy, closeTo(after.top + after.height / 4, 1e-6));
    });

    test('масштаб упирается в пределы', () async {
      final screen = await screenOf(FakeSystemPdf());
      for (var i = 0; i < 40; i++) {
        screen.zoomBy(PdfViewerScreen.zoomStep);
      }
      expect(screen.scale, closeTo(608 / 800 * PdfViewerScreen.maxZoom, 1e-9));

      // `F2` из своего масштаба — к виду из настройки.
      screen.toggleFit();
      expect(screen.fits, isTrue);
      expect(screen.wholePage, isFalse);
    });
  });

  group('поиск по страницам', () {
    final found = [
      const PdfMatch(page: 0, rects: [Rect.fromLTWH(0.1, 0.1, 0.2, 0.02)]),
      const PdfMatch(page: 2, rects: [Rect.fromLTWH(0.5, 0.9, 0.2, 0.02)]),
    ];

    test('находит, считает и подводит показ к найденному', () async {
      final system = FakeSystemPdf(found: found);
      final screen = await screenOf(system);

      expect(await screen.finder.search('needle', caseSensitive: true), 2);
      expect(system.opened.single.searched.single, ('needle', true));
      expect(screen.finder.currentIndex, 1);
      expect(screen.offset.dy, 0, reason: 'первое и так видно');

      screen.finder.next();
      expect(screen.finder.currentIndex, 2);
      final page = screen.pageRects[2];
      expect(screen.offset.dy + screen.viewport.height, greaterThan(page.top + page.height * 0.9));

      // По кругу.
      screen.finder.next();
      expect(screen.finder.currentIndex, 1);
      screen.finder.previous();
      expect(screen.finder.currentIndex, 2);
    });

    test('выражений нет — и окно об этом знает', () async {
      final screen = await screenOf(FakeSystemPdf());
      expect(screen.finder.supportsRegex, isFalse);
    });
  });

  group('текст документа', () {
    test('достаётся по просьбе и один раз', () async {
      final system = FakeSystemPdf();
      final screen = await screenOf(system);
      expect(system.opened.single.textAsked, 0, reason: 'при открытии не платим');

      expect(await screen.loadText(), isTrue);
      screen.toggleText();
      expect(screen.showsText, isTrue);
      expect(screen.text!.text, contains('second page'));

      await screen.loadText();
      expect(system.opened.single.textAsked, 1);
    });

    test('в тексте ищет поле, а не система — и выражением тоже', () async {
      final screen = await screenOf(FakeSystemPdf());
      await screen.loadText();
      screen.toggleText();

      expect(screen.finder.supportsRegex, isTrue);
    });

    test('у скана текста нет — вид не меняется', () async {
      // Раннер отдаёт пустую строку, когда ни на одной странице нет текста.
      final scan = await screenOf(FakeSystemPdf(text: ''));

      expect(await scan.loadText(), isFalse);
      scan.toggleText();
      expect(scan.showsText, isFalse);
    });
  });

  test('закрыли показ — документ в системе отпущен', () async {
    final system = FakeSystemPdf();
    final screen = await screenOf(system);

    screen.close();

    expect(system.opened.single.closed, isTrue);
  });
}
