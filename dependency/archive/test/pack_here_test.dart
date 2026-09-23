import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_archive/fc_archive.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

/// Упаковка в каталог **своей** панели (`docs/spec/archive-here.md`, §4).
void main() {
  late Directory temp;
  late String root;
  late String source;
  late String other;
  late AppRuntime runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_pack_here');
    root = await temp.resolveSymbolicLinks();
    source = p.join(root, 'source');
    other = p.join(root, 'other');
    await Directory(source).create();
    await Directory(other).create();
    await File(p.join(source, 'notes.txt')).writeAsString('заметки');

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const ZipArchiver(), const ArchiveHere()],
      backend: [const ZipArchiver(), const ArchiveHere()],
      settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(other)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  testWidgets('архив ложится в свою панель, а не в соседнюю', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    runtime.app.left.setCursorToName('notes.txt');
    await tester.pumpAndSettle();

    // Мимо окна: имя задано параметром — так команду зовут сценарий и палитра.
    final command = runtime.commands.create(PackHereCommand.commandId)!;
    final archive = File(p.join(source, 'work.zip'));
    await tester.runAsync(() async {
      await command.executeWith(const {PackHereCommand.nameParam: 'work'});
      await waitUntilAsync(archive.exists, tries: 400, step: const Duration(milliseconds: 10));
    });
    await tester.pump();

    expect(archive.existsSync(), isTrue, reason: 'архив лёг в свою панель');
    expect(File(p.join(other, 'work.zip')).existsSync(), isFalse, reason: 'соседняя панель тут ни при чём');
  });

  testWidgets('формат выбирается списком объявленных упаковщиков', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    runtime.app.left.setCursorToName('notes.txt');
    await tester.pumpAndSettle();

    runtime.commands.run(PackHereCommand.commandId, const CommandInvocation());
    await tester.pumpAndSettle();

    // Объявлен один упаковщик — он и выбран; строка формата всё равно есть:
    // она говорит, во что паковать.
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('ZIP'), findsWidgets);
  });
}
