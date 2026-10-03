import 'dart:ui';

import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Оглавление, ссылки и история переходов (`docs/spec/pdf-viewer.md`, §16).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const outline = [
    PdfOutlineItem(depth: 0, title: 'Introduction', target: PdfTarget(0)),
    PdfOutlineItem(depth: 1, title: 'Getting started', target: PdfTarget(1, top: 0.5)),
    PdfOutlineItem(depth: 0, title: 'Reference', target: PdfTarget(4)),
  ];

  late AppRuntime runtime;
  late FakeSystemPdf system;

  Future<void> start(FakeSystemPdf pdf) async {
    system = pdf;
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/doc.pdf', content: '${pdfHeader}one'.codeUnits),
      ])..home = '/home',
      modules: [...featureModules(), FakeSystemPdfModule(system)],
    );
    await runtime.app.start();
  }

  Future<PdfViewerScreen> view() async {
    runtime.app.left.setCursorToName('doc.pdf');
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
    final screen = runtime.app.view.contentAt(ViewportPosition.fullscreen)! as PdfViewerScreen;
    screen.layoutIn(const Size(632, 500));
    return screen;
  }

  FakeSystemPdf pdf({List<PdfOutlineItem> items = outline}) =>
      FakeSystemPdf(pages: List.filled(6, const Size(600, 800)), outline: items);

  group('оглавление', () {
    test('F6 открывает его окном палитры: порядок документа, отступы, номера страниц', () async {
      await start(pdf());
      await view();

      expect(runtime.commands.dispatch(KeyCombination.parse('F6')), isTrue);
      await pumpEventQueue();

      final dialog = runtime.app.view.dialogs.last.content as FcPickPalette;
      expect(dialog.keepOrder, isTrue);
      expect([for (final row in dialog.rows) row.title], ['Introduction', 'Getting started', 'Reference']);
      expect([for (final row in dialog.rows) row.indent], [0, 1, 0]);
      expect([for (final row in dialog.rows) row.trailing], ['1', '2', '5']);
    });

    test('курсор стоит на текущем разделе', () async {
      await start(pdf());
      final screen = await view();
      screen.scrollTo(Offset(0, screen.topOf(2)));

      expect(runtime.commands.dispatch(KeyCombination.parse('F6')), isTrue);
      await pumpEventQueue();

      final dialog = runtime.app.view.dialogs.last.content as FcPickPalette;
      expect(dialog.initial, '1', reason: 'третья страница — внутри «Getting started»');
    });

    test('выбор ведёт к разделу и закрывает окно', () async {
      await start(pdf());
      final screen = await view();

      expect(runtime.commands.dispatch(KeyCombination.parse('F6')), isTrue);
      await pumpEventQueue();
      (runtime.app.view.dialogs.last.content as FcPickPalette).onPick('2');
      await pumpEventQueue();

      expect(runtime.app.view.dialogs, isEmpty);
      expect(screen.offset.dy, screen.topOf(4));
      expect(screen.canGoBack, isTrue);
    });

    test('без оглавления — сообщение, окна нет', () async {
      await start(pdf(items: const []));
      await view();

      expect(runtime.commands.dispatch(KeyCombination.parse('F6')), isTrue);
      await pumpEventQueue();

      expect(runtime.app.view.dialogs, isEmpty);
      expect(runtime.app.toasts.current?.message, contains('table of contents'));
    });

    test('достаётся один раз', () async {
      await start(pdf());
      final screen = await view();
      await screen.loadOutline();
      await screen.loadOutline();

      expect(system.opened.single.outlineAsked, 1);
    });
  });

  group('назад и вперёд', () {
    test('Alt-Left возвращает на место до перехода, Alt-Right — обратно', () async {
      await start(pdf());
      final screen = await view();
      final page = screen.pageRects[1];
      screen.scrollTo(Offset(0, page.top + page.height / 3));
      final before = screen.offset.dy;

      screen.jumpTo(const PdfTarget(4));
      final after = screen.offset.dy;
      expect(after, isNot(before));

      expect(runtime.commands.dispatch(KeyCombination.parse('Alt-Left')), isTrue);
      expect(screen.offset.dy, closeTo(before, 1e-6));

      expect(runtime.commands.dispatch(KeyCombination.parse('Alt-Right')), isTrue);
      expect(screen.offset.dy, closeTo(after, 1e-6));
    });

    test('место помнится долей: после масштаба возвращаемся туда же', () async {
      await start(pdf());
      final screen = await view();
      final page = screen.pageRects[1];
      screen.scrollTo(Offset(0, page.top + page.height / 3));

      screen.jumpTo(const PdfTarget(4));
      screen.zoomBy(PdfViewerScreen.zoomStep);
      screen.goBack();

      final zoomed = screen.pageRects[1];
      expect(screen.offset.dy, closeTo(zoomed.top + zoomed.height / 3, 1e-6));
    });

    test('без перехода возвращаться некуда — команды недоступны', () async {
      await start(pdf());
      final screen = await view();
      screen.scrollBy(const Offset(0, 300));

      expect(screen.canGoBack, isFalse, reason: 'прокрутка — чтение, а не переход');
      expect(runtime.commands.isExecutable(runtime.commands.find(StepPdfHistoryCommand.backCommandId)!), isFalse);
    });

    test('доля на странице: переход ставит место назначения под верхний край', () async {
      await start(pdf());
      final screen = await view();

      screen.jumpTo(const PdfTarget(1, top: 0.5));

      final page = screen.pageRects[1];
      expect(screen.offset.dy, closeTo(page.top + page.height / 2 - PdfViewerScreen.margin, 1e-6));
    });
  });

  group('ссылки', () {
    final links = {
      0: const [
        PdfLink(rect: Rect.fromLTWH(0.1, 0.1, 0.3, 0.05), target: PdfTarget(3)),
        PdfLink(rect: Rect.fromLTWH(0.5, 0.5, 0.3, 0.05), url: 'https://example.org'),
      ],
    };

    test('ссылку под точкой находит; на пустом месте — нет', () async {
      await start(FakeSystemPdf(pages: List.filled(6, const Size(600, 800)), links: links));
      final screen = await view();
      screen.linksOf(0);
      await pumpEventQueue();

      final page = screen.pageRects[0];
      final internal = screen.linkAt(Offset(page.left + page.width * 0.2, page.top + page.height * 0.12));
      expect(internal?.target, const PdfTarget(3));

      final external = screen.linkAt(Offset(page.left + page.width * 0.6, page.top + page.height * 0.52));
      expect(external?.url, 'https://example.org');

      expect(screen.linkAt(Offset(page.left + 2, page.top + 2)), isNull);
    });
  });
}
