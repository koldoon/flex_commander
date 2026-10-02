import 'package:fc_pdf_viewer/fc_pdf_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_pdf.dart';

/// Без просмотрщика PDF приложение собирается, а `.pdf` открывается как
/// раньше: возможность приносит модуль.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/a.pdf', content: '${pdfHeader}one'.codeUnits),
      ])..home = '/home',
      modules: [...featureModules().where((module) => module is! PdfViewer), FakeSystemPdfModule(FakeSystemPdf())],
    );
    await runtime.app.start();
  });

  test('`.pdf` открывает кто-то другой', () async {
    runtime.app.left.setCursorToName('a.pdf');
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();

    final shown = runtime.app.view.contentAt(ViewportPosition.fullscreen);
    expect(shown, isNotNull);
    expect(shown, isNot(isA<PdfViewerScreen>()));
  });

  test('команд просмотрщика PDF нет вовсе', () async {
    expect(runtime.commands.find('pdf.fit'), isNull);
    expect(runtime.commands.find('pdf.find'), isNull);
  });
}
