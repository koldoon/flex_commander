import 'dart:convert';

import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Без модуля `.md` снова открывает текстовый просмотрщик.
///
/// Это и есть проверка правила «возможность приносит модуль»: выключили —
/// пропала вёрстка, а не сборка. Текстовый держит `md` среди своих расширений
/// именно затем, чтобы остаться запасным.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/readme.md', content: utf8.encode('# Заголовок\n\nАбзац.\n')),
      ])..home = '/home',
      modules: [...featureModules().where((module) => module is! MarkdownViewer)],
    );
    await runtime.app.start();
  });

  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  test('`.md` открывает текстовый', () async {
    await view('readme.md');

    expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isA<TextViewerScreen>());
  });

  test('команды переключения нет вовсе', () {
    expect(runtime.commands.find(ToggleMarkdownFormatCommand.commandId), isNull);
  });

  test('и рисовальщиков врезок никто не спрашивает', () {
    // Реестр из шага 1 пуст — и это законный вид приложения.
    expect(runtime.app.markdownBlocks, isEmpty);
  });

  test('а приложение живо', () {
    expect(runtime.commands.find(ViewFileCommand.commandId), isNotNull);
    expect(runtime.app.left, isNotNull);
  });
}
