import 'package:fc_api/fc_api.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Показ без приложения: свёрстанный документ и его исходник.
void main() {
  // Ссылка отдельным абзацем: нажатие в тесте приходится в середину виджета,
  // и внутри длинной строки оно попало бы мимо неё.
  const notes = '# Заголовок\n\nАбзац про дело.\n\n[сюда](https://example.org)\n';

  MarkdownViewerScreen screenOf({bool formatted = true, SystemOpener? openWith}) => MarkdownViewerScreen(
    entry: FileEntry(name: 'readme.md', kind: EntryKind.file, path: '/home/readme.md', size: notes.length),
    document: FcMarkdownDocument.parse(notes),
    settings: MarkdownViewerSettings(startFormatted: formatted),
    onSettingsChanged: () {},
    openWith: openWith,
  );

  testWidgets('свёрстанный документ показан текстом, а не разметкой', (tester) async {
    final screen = screenOf();
    await pumpScreen(tester, MarkdownViewerView(screen: screen));

    expect(find.text('Заголовок'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
    expect(find.byType(FcMarkdownView), findsOneWidget);

    screen.dispose();
    await disposeScreen(tester);
  });

  testWidgets('исходник показан тем же полем, что и у текстового просмотрщика', (tester) async {
    await withDesktopPlatform(() async {
      final screen = screenOf(formatted: false);
      await pumpScreen(tester, MarkdownViewerView(screen: screen));

      expect(find.byType(FcTextView), findsOneWidget);
      expect(find.byType(FcMarkdownView), findsNothing);

      screen.dispose();
      await disposeScreen(tester);
    });
  });

  testWidgets('переключение перерисовывает показ', (tester) async {
    final screen = screenOf();
    await pumpScreen(tester, MarkdownViewerView(screen: screen));
    expect(find.byType(FcMarkdownView), findsOneWidget);

    screen.toggleFormat();
    await tester.pump();

    expect(find.byType(FcMarkdownView), findsNothing);

    screen.dispose();
    await disposeScreen(tester);
  });

  testWidgets('внешняя ссылка уходит системе', (tester) async {
    String? opened;
    final screen = screenOf(
      openWith: (path) async {
        opened = path;
      },
    );
    await pumpScreen(tester, MarkdownViewerView(screen: screen));

    await tester.tap(find.textContaining('сюда'));
    await tester.pump();

    expect(opened, 'https://example.org');

    screen.dispose();
    await disposeScreen(tester);
  });

  testWidgets('без службы открытия нажатие не роняет показ', (tester) async {
    final screen = screenOf();
    await pumpScreen(tester, MarkdownViewerView(screen: screen));

    await tester.tap(find.textContaining('сюда'));
    await tester.pump();

    expect(tester.takeException(), isNull);

    screen.dispose();
    await disposeScreen(tester);
  });
}
