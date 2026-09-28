import 'dart:convert';

import 'package:fc_markdown_viewer/fc_markdown_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Картинки документа читаются через тот же источник, что и он сам.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/logo.png', content: utf8.encode('это логотип')),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/docs/readme.md', content: utf8.encode('# Документ\n')),
        FakeEntry.file('/home/docs/shot.png', content: utf8.encode('это снимок')),
        FakeEntry.directory('/home/docs/pics'),
        FakeEntry.file('/home/docs/pics/deep.png', content: utf8.encode('это вложенная')),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<MarkdownViewerScreen> open() async {
    await runtime.app.left.openPath('/home/docs');
    await pumpEventQueue();
    runtime.app.left.setCursorToName('readme.md');
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();

    return runtime.app.view.contentAt(ViewportPosition.fullscreen)! as MarkdownViewerScreen;
  }

  Future<String> read(MarkdownViewerScreen screen, String path) async => utf8.decode(await screen.resolveImage!(path));

  test('соседний файл — рядом с документом, а не рядом с панелью', () async {
    final screen = await open();

    expect(await read(screen, 'shot.png'), 'это снимок');
  });

  test('`./` ничего не меняет', () async {
    final screen = await open();

    expect(await read(screen, './shot.png'), 'это снимок');
  });

  test('`../` поднимается на уровень выше', () async {
    final screen = await open();

    expect(await read(screen, '../logo.png'), 'это логотип');
  });

  test('вложенный каталог читается тоже', () async {
    final screen = await open();

    expect(await read(screen, 'pics/deep.png'), 'это вложенная');
  });

  test('путь от корня берётся как есть', () async {
    final screen = await open();

    expect(await read(screen, '/home/logo.png'), 'это логотип');
  });
}
