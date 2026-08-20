import 'dart:io';
import 'package:fc_7z/fc_7z.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Окно команды упаковки в 7z: форма с именем и степенью сжатия.
///
/// Форма своя, а не общая с zip: модули друг о друге не знают, и связывать их
/// ради полутора экранов кода значило бы отменить ту самую независимость, ради
/// которой они и заведены. Общее вынесется, когда появится третий архиватор и
/// станет видно, что именно общее.
void main() {
  late Directory temp;
  late String source;
  late String target;
  late AppRuntime runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_7z_dialog');
    final root = await temp.resolveSymbolicLinks();
    source = p.join(root, 'source');
    target = p.join(root, 'target');
    await Directory(source).create();
    await Directory(target).create();
    await File(p.join(source, 'notes.txt')).writeAsString('заметки');

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const SevenZipArchiver()],
      settings: AppSettings(left: PanelSettings.defaults(source), right: PanelSettings.defaults(target)),
    );
    await runtime.app.start();
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  /// Рисует окно команды так же, как его рисует ядро: рама и оформление снаружи.
  Future<AppCommand> pumpDialog(WidgetTester tester) async {
    runtime.app.left.setCursorToName('notes.txt');
    final command = runtime.commands.create(CreateSevenZipArchiveCommand.commandId)!;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            // Контекст берётся из дерева — так же, как его берёт слой окон
            // команд в ядре.
            child: SizedBox(width: 500, child: Builder(builder: (context) => command.getDialog(context)!)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return command;
  }

  testWidgets('форма показывает имя, приёмник, сжатие и две кнопки', (tester) async {
    await pumpDialog(tester);

    // Имя предложено по объекту под курсором.
    expect(find.text('notes.txt.7z'), findsOneWidget);
    expect(find.text('Archive name'), findsOneWidget);
    // Куда ляжет архив — видно, а не угадывается.
    expect(find.text('Create in'), findsOneWidget);
    expect(find.text(target), findsOneWidget);

    // Степень сжатия: все уровни и обе кнопки.
    expect(find.text('Compression'), findsOneWidget);
    for (final title in ['Store', 'Fast', 'Normal', 'Best']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('по умолчанию выбрано среднее сжатие', (tester) async {
    final command = await pumpDialog(tester);

    expect(command.parameters.values[CreateSevenZipArchiveCommand.compressionParam], SevenZipCompression.normal.name);
  });

  testWidgets('введённое имя доходит до команды по мере ввода', (tester) async {
    final command = await pumpDialog(tester);

    await tester.enterText(find.byType(FcTextField).last, 'photos');
    await tester.pump();

    // Enter обрабатывает ядро, поэтому параметр должен быть на месте раньше.
    expect(command.parameters.values[CreateSevenZipArchiveCommand.nameParam], 'photos');
  });

  testWidgets('выбранное сжатие доходит до команды', (tester) async {
    final command = await pumpDialog(tester);

    await tester.tap(find.text('Best'));
    await tester.pump();

    expect(command.parameters.values[CreateSevenZipArchiveCommand.compressionParam], SevenZipCompression.best.name);
  });

  testWidgets('Cancel закрывает окно, ничего не создавая', (tester) async {
    final command = await pumpDialog(tester);
    runtime.commands.run(CreateSevenZipArchiveCommand.commandId);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(Directory(target).listSync(), isEmpty);
    expect(command.isRunning, isFalse);
  });
}
