import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подставной рисовальщик врезки: рисует узнаваемый текст.
class _BlockModule implements FcFrontendModule {
  const _BlockModule();

  static const String mark = 'нарисовано рисовальщиком';

  @override
  String get id => 'test.block';

  @override
  String get title => 'Test block';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.markdownBlock(
      MarkdownBlockSpec(
        id: 'toy',
        title: 'Toy',
        accepts: (language) => language == 'toy',
        build: (context, request) => const Text(mark, textDirection: TextDirection.ltr),
      ),
    );
  }
}

/// Объявленные модулями рисовальщики врезок доходят до показа — **в обоих
/// местах**.
///
/// Проверка заведена по живой находке: показ читал приложение только когда стоял
/// в панели, и во весь экран список рисовальщиков уходил пустым. Диаграмма
/// оставалась кодом, и сказать об этом было некому — отказа ведь не было.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const document = '# Документ\n\n```toy\nвсё равно что\n```\n';

  MarkdownViewerScreen screenAt(ViewerPlace place) => MarkdownViewerScreen(
    entry: FileEntry(name: 'a.md', kind: EntryKind.file, path: '/home/a.md', size: document.length),
    document: FcMarkdownDocument.parse(document),
    settings: MarkdownViewerSettings(),
    onSettingsChanged: () {},
    place: place,
  );

  /// Приложение с объявленным рисовальщиком — его и спросит показ.
  Future<Application> appWithBlock() async {
    final runtime = await testApp(
      provider: InMemoryContentProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: [...featureModules(), const _BlockModule()],
    );
    await runtime.app.start();

    return runtime.app;
  }

  testWidgets('во весь экран врезку рисует объявленный рисовальщик', (tester) async {
    final screen = screenAt(ViewerPlace.fullscreen);

    await pumpScreen(tester, MarkdownViewerView(screen: screen), app: await appWithBlock());

    expect(find.text(_BlockModule.mark), findsOneWidget);

    screen.dispose();
    await disposeScreen(tester);
  });

  testWidgets('и в панели тоже', (tester) async {
    final screen = screenAt(ViewerPlace.panel);

    await pumpScreen(tester, MarkdownViewerView(screen: screen), app: await appWithBlock());

    expect(find.text(_BlockModule.mark), findsOneWidget);

    screen.dispose();
    await disposeScreen(tester);
  });
}
