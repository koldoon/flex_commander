import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Выделение мышью и копирование в буфер обмена.
void main() {
  late AppRuntime runtime;
  late FakeClipboard clipboard;

  setUp(() async {
    clipboard = FakeClipboard();
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('первая строка\nвторая строка\nтретья строка')),
      ])..home = '/home',
      modules: featureModules(),
      clipboard: clipboard,
    );
    await runtime.app.start();
  });

  Future<ViewerScreen> openViewer() async {
    runtime.app.left.setCursorToName('notes.txt');
    await (runtime.commands.create(ViewFileCommand.commandId)!).execute();
    return runtime.app.screens.active! as ViewerScreen;
  }

  Future<void> pumpViewer(WidgetTester tester, ViewerScreen screen) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: Builder(builder: screen.build)),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('пока ничего не выделено, копировать нечего', () async {
    await openViewer();

    final copy = runtime.commands.find(CopySelectionCommand.commandId)!;

    // Кнопка в ряду останется приглушённой, а не сделает вид, что сработала.
    expect(runtime.commands.isExecutable(copy), isFalse);
  });

  test('выделенное уходит в буфер по Cmd-C', () async {
    final screen = await openViewer();
    screen.setSelection('вторая строка');

    expect(runtime.commands.dispatch(KeyCombination.parse('Cmd-C')), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(clipboard.text, 'вторая строка');
    // Случилось и закончилось — о таком говорят всплывающим сообщением.
    expect(runtime.app.toasts.current?.message, contains('Copied'));
  });

  test('в панелях Cmd-C просмотрщику не принадлежит', () {
    expect(runtime.commands.commandFor(KeyCombination.parse('Cmd-C'))?.id, isNot(CopySelectionCommand.commandId));
  });

  testWidgets('текст обёрнут выделением, и оно сообщает экрану', (tester) async {
    final screen = await openViewer();
    await pumpViewer(tester, screen);

    // Обычное текстовое выделение мышью: тянут по строкам.
    expect(find.byType(SelectionArea), findsOneWidget);

    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    area.onSelectionChanged!(const SelectedContent(plainText: 'первая'));

    expect(screen.selection, 'первая');
  });

  testWidgets('снятое выделение снова делает копирование недоступным', (tester) async {
    final screen = await openViewer();
    await pumpViewer(tester, screen);

    final area = tester.widget<SelectionArea>(find.byType(SelectionArea));
    area.onSelectionChanged!(const SelectedContent(plainText: 'первая'));
    expect(screen.selection, isNotEmpty);

    area.onSelectionChanged!(null);

    expect(screen.selection, isEmpty);
    expect(runtime.commands.isExecutable(runtime.commands.find(CopySelectionCommand.commandId)!), isFalse);
  });
}
