import 'dart:io';
import 'package:fc_7z/fc_7z.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:fc_local_fs/fc_local_fs.dart';
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
    // Окно показывает сама команда: она строит его и уходит. Рисуется дальше
    // то, что она отдала рабочей области.
    await command.executeWith();
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

  /// Сама рамка списка сжатия, а не весь контрол: внешний бокс растянут
  /// столбцом значений, и щелчок по его середине уходит мимо рамки.
  Finder compression() =>
      find.descendant(of: find.byType(FcSelect<SevenZipCompression>), matching: find.byType(Opacity));

  testWidgets('форма показывает имя, приёмник, сжатие и две кнопки', (tester) async {
    await pumpDialog(tester);

    // Имя предложено по объекту под курсором.
    expect(find.text('notes.txt.7z'), findsOneWidget);
    expect(find.text('Archive name'), findsOneWidget);
    // Куда ляжет архив — видно, а не угадывается.
    expect(find.text('Create in'), findsOneWidget);
    expect(find.text(target), findsOneWidget);

    // Степень сжатия: пока список не раскрыт, видно только выбранное — в этом
    // и разница с прежним переключателем, у которого все уровни стояли разом.
    expect(find.text('Compression'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Store'), findsNothing);

    await tester.tap(compression());
    await tester.pumpAndSettle();
    for (final title in ['Store', 'Fast', 'Normal', 'Best']) {
      // Внутри самого списка: строка в нём набрана разметкой, и искать её
      // приходится через `findRichText`, а тот заодно видит и подпись в поле.
      expect(
        find.descendant(of: find.byType(FcPickList), matching: find.text(title, findRichText: true)),
        findsOneWidget,
      );
    }
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('по умолчанию выбрано среднее сжатие', (tester) async {
    await pumpDialog(tester);

    expect(
      tester.widget<FcSelect<SevenZipCompression>>(find.byType(FcSelect<SevenZipCompression>)).value,
      SevenZipCompression.normal,
    );
  });

  testWidgets('введённое имя доходит до команды по мере ввода', (tester) async {
    await pumpDialog(tester);

    await tester.enterText(find.byType(FcTextField).last, 'photos');
    await tester.pump();

    // Стёртое имя — самый короткий способ увидеть, что значение дошло: работа
    // отказывается заводиться, не дойдя до диска, и говорит об этом в форме.
    await tester.enterText(find.byType(FcTextField).last, '');
    await tester.pump();
    await tester.tap(find.widgetWithText(FcButton, 'Create'));
    await tester.pump();

    expect(find.text(const FsError('', FsErrorKind.invalidName).message), findsOneWidget);
  });

  testWidgets('выбранное сжатие доходит до команды', (tester) async {
    await pumpDialog(tester);

    await tester.tap(compression());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(FcPickList), matching: find.text('Best', findRichText: true)));
    await tester.pumpAndSettle();

    expect(
      tester.widget<FcSelect<SevenZipCompression>>(find.byType(FcSelect<SevenZipCompression>)).value,
      SevenZipCompression.best,
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
