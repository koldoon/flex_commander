import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_archive/fc_archive.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Окно упаковки по месту: имя, формат списком и довод формата
/// (`docs/spec/archive-here.md`, §4).
void main() {
  late Directory temp;
  late String source;
  late AppRuntime runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_pack_here_dialog');
    final root = await temp.resolveSymbolicLinks();
    source = p.join(root, 'source');
    await Directory(source).create();
    await File(p.join(source, 'notes.txt')).writeAsString('заметки');

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const ZipArchiver(), const ArchiveHere()],
      backend: [const ZipArchiver(), const ArchiveHere()],
      settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(root)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AppCommand> pumpDialog(WidgetTester tester) async {
    runtime.app.left.setCursorToName('notes.txt');
    final command = runtime.commands.create(PackHereCommand.commandId)!;
    await command.executeWith();
    final spec = runtime.app.view.dialogs.single;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(body: Center(child: SizedBox(width: 500, child: spec.content))),
      ),
    );
    await tester.pumpAndSettle();
    return command;
  }

  testWidgets('форма показывает место, имя, формат и довод формата', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Create in'), findsOneWidget);
    expect(find.text('Archive name'), findsOneWidget);
    expect(find.text('Format'), findsOneWidget);
    // Место не правится: приёмник — своя же панель.
    expect(tester.widgetList<FcTextField>(find.byType(FcTextField)).where((field) => !field.enabled), hasLength(1));
    // Довод формата приходит объявлением упаковщика: у zip это сжатие.
    expect(find.text('Compression'), findsOneWidget);
  });

  testWidgets('имя из поля доходит до работы, а не остаётся в нём', (tester) async {
    await pumpDialog(tester);

    // Стёртое имя — самый короткий способ это увидеть: работа отказывается
    // заводиться, не дойдя до диска, и говорит об этом в той же форме.
    await tester.enterText(find.byWidgetPredicate((widget) => widget is FcTextField && widget.enabled), '');
    await tester.pump();
    await tester.tap(find.widgetWithText(FcButton, 'Create'));
    await tester.pump();

    expect(find.text(const FsError('', FsErrorKind.invalidName).message), findsOneWidget);
  });
}
