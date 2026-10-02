import 'dart:ui';

import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// PDF в собранном приложении: `F3` открывает страницы, клавиши делают своё,
/// быстрый просмотр отпускает документы.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;
  late FakeSystemPdf system;
  const right = ViewportPosition.right;

  setUp(() async {
    system = FakeSystemPdf(
      found: const [
        PdfMatch(page: 1, rects: [Rect.fromLTWH(0.1, 0.5, 0.2, 0.02)]),
      ],
    );
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/a.pdf', content: '${pdfHeader}one'.codeUnits),
        FakeEntry.file('/home/b.pdf', content: '${pdfHeader}two'.codeUnits),
        FakeEntry.file('/home/notes.txt', content: 'просто текст'.codeUnits),
      ])..home = '/home',
      modules: [...featureModules(), FakeSystemPdfModule(system)],
    );
    await runtime.app.start();
  });

  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  ViewportState? shownFullscreen() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  test('`.pdf` открывает просмотрщик PDF', () async {
    await view('a.pdf');

    final screen = shownFullscreen();
    expect(screen, isA<PdfViewerScreen>());
    expect((screen! as PdfViewerScreen).document.pageCount, 3);
  });

  test('текст по-прежнему открывает текстовый: реестр не перепутал', () async {
    await view('notes.txt');

    expect(shownFullscreen(), isA<TextViewerScreen>());
  });

  test('F5 показывает текст и возвращает страницы', () async {
    await view('a.pdf');
    final screen = shownFullscreen()! as PdfViewerScreen;

    expect(runtime.commands.dispatch(KeyCombination.parse('F5')), isTrue);
    await pumpEventQueue();
    expect(screen.showsText, isTrue);

    expect(runtime.commands.dispatch(KeyCombination.parse('F5')), isTrue);
    await pumpEventQueue();
    expect(screen.showsText, isFalse);
  });

  test('F7 ищет по страницам силами системы', () async {
    await view('a.pdf');
    final screen = shownFullscreen()! as PdfViewerScreen;

    await runtime.commands.create('pdf.find')!.executeWith({FcFindTextCommand.patternParam: 'needle'});
    await pumpEventQueue();

    expect(system.opened.single.searched.single.$1, 'needle');
    expect(screen.finder.matchCount, 1);
    expect(screen.pageFinder.current?.page, 1);
  });

  test('F2 переключает «по ширине / страница целиком»', () async {
    await view('a.pdf');
    final screen = shownFullscreen()! as PdfViewerScreen;
    expect(screen.wholePage, isFalse);

    expect(runtime.commands.dispatch(KeyCombination.parse('F2')), isTrue);
    await pumpEventQueue();
    expect(screen.wholePage, isTrue);
  });

  test('закрыли показ — документ в системе отпущен', () async {
    await view('a.pdf');
    expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
    await pumpEventQueue();

    expect(shownFullscreen(), isNull);
    expect(system.opened.single.closed, isTrue);
  });

  test('быстрый просмотр меняет документ на шаг курсора и отпускает прежний', () async {
    runtime.app.left.setCursorToName('a.pdf');
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
    await pumpEventQueue();

    final host = runtime.app.view.contentAt(right)! as QuickViewHost;
    expect(innermost(host), isA<PdfViewerScreen>());

    runtime.app.left.setCursorToName('b.pdf');
    await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
    await pumpEventQueue();

    expect((innermost(host) as PdfViewerScreen).entry.name, 'b.pdf');
    expect(system.opened.first.closed, isTrue, reason: 'иначе раннер копил бы их все');
    expect(system.opened.last.closed, isFalse);
  });
}
