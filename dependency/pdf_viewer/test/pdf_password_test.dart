import 'package:fc_api/fc_api.dart';
import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Запертый PDF: `F3` спрашивает пароль общим окном, быстрый просмотр — никогда
/// (`docs/spec/pdf-viewer.md`, §15).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;
  late FakeSystemPdf system;

  setUp(() async {
    system = FakeSystemPdf(locked: true, password: 'secret');
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/locked.pdf', content: '${pdfHeader}one'.codeUnits),
        FakeEntry.file('/home/notes.txt', content: 'просто текст'.codeUnits),
      ])..home = '/home',
      modules: [...featureModules(), FakeSystemPdfModule(system)],
    );
    await runtime.app.start();
  });

  ViewportState? shownFullscreen() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  /// `F3`. Ответ — когда открытие закончится; вопрос появляется раньше.
  Future<void> pressF3() {
    runtime.app.left.setCursorToName('locked.pdf');
    return runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
  }

  Future<void> answer(String? password) async {
    runtime.app.credentials.answer(password == null ? null : Credential.password(password));
    await pumpEventQueue();
  }

  test('F3 спрашивает пароль об этом файле, и верный открывает', () async {
    final opening = pressF3();
    await pumpEventQueue();

    final asked = runtime.app.credentials.pending;
    expect(asked?.realm, 'pdf:/home/locked.pdf');
    expect(asked?.message, 'locked.pdf');
    expect(asked?.retry, isFalse);
    expect(shownFullscreen(), isNull);

    await answer('secret');
    await opening;

    expect(shownFullscreen(), isA<PdfViewerScreen>());
    expect(runtime.app.credentials.pending, isNull);
  });

  test('неверный — тот же вопрос с пометкой, и только потом верный', () async {
    final opening = pressF3();
    await pumpEventQueue();

    await answer('wrong');
    expect(runtime.app.credentials.pending?.retry, isTrue);
    expect(shownFullscreen(), isNull);

    await answer('secret');
    await opening;

    expect(system.opened.single.tried, ['wrong', 'secret']);
    expect(shownFullscreen(), isA<PdfViewerScreen>());
  });

  test('закрыли окно — показа нет, сообщения нет, документ отпущен', () async {
    final opening = pressF3();
    await pumpEventQueue();

    await answer(null);
    await opening;

    expect(shownFullscreen(), isNull);
    expect(runtime.app.toasts.current, isNull, reason: 'человек сам передумал');
    expect(system.opened.single.closed, isTrue);
  });

  test('второй F3 на том же файле пароля не спрашивает', () async {
    final first = pressF3();
    await pumpEventQueue();
    await answer('secret');
    await first;
    expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
    await pumpEventQueue();

    await pressF3();
    await pumpEventQueue();

    expect(runtime.app.credentials.pending, isNull);
    expect(shownFullscreen(), isA<PdfViewerScreen>());
    expect(system.opened.last.tried, ['secret']);
  });

  group('быстрый просмотр', () {
    Future<ViewportState?> quickView() async {
      runtime.app.left.setCursorToName('locked.pdf');
      expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
      await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
      await pumpEventQueue();
      final host = runtime.app.view.contentAt(ViewportPosition.right)! as QuickViewHost;
      return innermost(host);
    }

    test('не спрашивает: окно от шага курсора — ловушка', () async {
      final shown = await quickView();

      expect(runtime.app.credentials.pending, isNull);
      expect(shown, isNot(isA<PdfViewerScreen>()));
      expect(system.opened.single.closed, isTrue);
    });

    test('после пароля, названного по F3, открывает', () async {
      final opening = pressF3();
      await pumpEventQueue();
      await answer('secret');
      await opening;
      expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
      await pumpEventQueue();

      expect(await quickView(), isA<PdfViewerScreen>());
      expect(runtime.app.credentials.pending, isNull);
    });
  });
}
