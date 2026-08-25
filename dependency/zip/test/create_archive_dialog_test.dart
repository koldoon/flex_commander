import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_zip/fc_zip.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/local_fs/local_tree_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Окно команды упаковки: форма с именем и степенью сжатия.
void main() {
  late Directory temp;
  late String source;
  late String target;
  late AppRuntime runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_zip_dialog');
    final root = await temp.resolveSymbolicLinks();
    source = p.join(root, 'source');
    target = p.join(root, 'target');
    await Directory(source).create();
    await Directory(target).create();
    await File(p.join(source, 'notes.txt')).writeAsString('заметки');

    runtime = await testApp(
      provider: LocalTreeProvider(homePath: root, readInIsolate: false),
      modules: [const ZipArchiver()],
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
    final command = runtime.commands.create(CreateZipArchiveCommand.commandId)!;
    // Окно показывает сама команда: она строит его и уходит. Рисуется дальше
    // то, что она отдала рабочей области.
    await command.execute();
    final spec = runtime.app.view.dialogs.single;

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
            child: SizedBox(width: 500, child: spec.content),
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
    expect(find.text('notes.txt.zip'), findsOneWidget);
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

  testWidgets('ссылками распоряжается флажок, и по умолчанию он снят', (tester) async {
    // Как в mc: ссылка остаётся ссылкой, а не подменяется содержимым цели.
    await pumpDialog(tester);

    expect(find.text('Follow symlinks'), findsOneWidget);
    expect(tester.widget<FcCheckbox>(find.byType(FcCheckbox)).value, isFalse);

    await tester.tap(find.text('Follow symlinks'));
    await tester.pump();

    expect(tester.widget<FcCheckbox>(find.byType(FcCheckbox)).value, isTrue);
  });

  testWidgets('по умолчанию выбрано среднее сжатие', (tester) async {
    await pumpDialog(tester);

    expect(
      tester.widget<FcRadioGroup<ZipCompression>>(find.byType(FcRadioGroup<ZipCompression>)).value,
      ZipCompression.normal,
    );
  });

  testWidgets('имя из поля доходит до работы, а не остаётся в нём', (tester) async {
    await pumpDialog(tester);

    // Стёртое имя — самый короткий способ это увидеть: работа отказывается
    // заводиться, не дойдя до диска, и говорит об этом в той же форме.
    // Проверять по созданному архиву нельзя: настоящего похода к диску
    // виджетный тест не дожидается.
    await tester.enterText(find.byType(FcTextField).last, '');
    await tester.pump();
    await tester.tap(find.widgetWithText(FcButton, 'Create'));
    await tester.pump();

    expect(find.text(const FsError('', FsErrorKind.invalidName).message), findsOneWidget);
  });

  testWidgets('выбранное сжатие доходит до работы', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Best'));
    await tester.pump();

    expect(
      tester.widget<FcRadioGroup<ZipCompression>>(find.byType(FcRadioGroup<ZipCompression>)).value,
      ZipCompression.best,
    );
  });

  testWidgets('Cancel закрывает окно, ничего не создавая', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(Directory(target).listSync(), isEmpty);
    expect(runtime.app.view.dialogs, isEmpty);
  });
}
