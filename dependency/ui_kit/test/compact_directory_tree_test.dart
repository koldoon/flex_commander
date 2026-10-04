import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дерево выбора места со склейкой цепочек
/// (`docs/spec/panel-view-compact-tree.md`, §13).
void main() {
  FileEntry dir(String path) => FileEntry(
    name: path.substring(path.lastIndexOf('/') + 1),
    kind: EntryKind.directory,
    path: path,
    directoryPath: path.substring(0, path.lastIndexOf('/')),
  );
  FileEntry file(String path) => FileEntry(
    name: path.substring(path.lastIndexOf('/') + 1),
    kind: EntryKind.file,
    path: path,
    directoryPath: path.substring(0, path.lastIndexOf('/')),
  );

  final disk = <String, List<FileEntry>>{
    '/home': [dir('/home/src'), dir('/home/one'), file('/home/top.json')],
    '/home/src': [dir('/home/src/main')],
    '/home/src/main': [dir('/home/src/main/java')],
    '/home/src/main/java': [file('/home/src/main/java/a.json'), file('/home/src/main/java/b.json')],
    '/home/one': [file('/home/one/x.json')],
  };

  late String selected;

  Future<void> pump(WidgetTester tester, {required bool compact}) async {
    selected = '~';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: StatefulBuilder(
              builder:
                  (context, setState) => FcDirectoryTree(
                    // Как в окне выбора: корень — сокращение, настоящий путь
                    // дерево узнаёт от первой ветви.
                    root: '~',
                    rootTitle: 'Home',
                    children: (path) async => disk[path == '~' ? '/home' : path] ?? const [],
                    selected: selected,
                    shows: (entry) => entry.name.endsWith('.json'),
                    onSelected: (path, isFile) => setState(() => selected = path),
                    compact: compact,
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Подписи строк сверху вниз: у цепочки — голова и имя.
  List<String> rows(WidgetTester tester) => [
    for (final element in find.descendant(of: find.byType(ListView), matching: find.byType(Text)).evaluate())
      if ((element.widget as Text).data case final text? when text.isNotEmpty && text.codeUnitAt(0) < 0xE000) text,
    for (final name in tester.widgetList<FcChainName>(find.byType(FcChainName))) '${name.head}/${name.name}',
  ];

  testWidgets('без флага — прежнее дерево: каталог раскрывается на ступень', (tester) async {
    await pump(tester, compact: false);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    expect(find.byType(FcChainName), findsNothing);
    expect(rows(tester), containsAll(['Home', 'src', 'main']));
    expect(rows(tester), isNot(contains('java')), reason: 'дальше ступени не раскрывается');
  });

  testWidgets('раскрыли — цепочка раскрылась до развилки и встала одной строкой', (tester) async {
    await pump(tester, compact: true);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    final chain = tester.widget<FcChainName>(find.byType(FcChainName));
    expect(chain.head, 'src/main');
    expect(chain.name, 'java');
    expect(find.text('a.json'), findsOneWidget);
    expect(find.text('b.json'), findsOneWidget);
  });

  testWidgets('выбранный каталог, ушедший в цепочку, переезжает на её строку', (tester) async {
    await pump(tester, compact: true);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    // В строке «Save to» должно стоять то место, что видно выделенным.
    expect(selected, '/home/src/main/java');
  });

  testWidgets('каталог с единственным файлом и корень не склеиваются', (tester) async {
    await pump(tester, compact: true);

    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();

    expect(find.text('one'), findsOneWidget);
    expect(find.text('x.json'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget, reason: 'корень стоит своей строкой');
  });

  testWidgets('← сворачивает самый глубокий, а со свёрнутой цепочки ведёт к родителю', (tester) async {
    await pump(tester, compact: true);
    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('a.json'), findsNothing, reason: 'свёрнут java');
    expect(find.byType(FcChainName), findsOneWidget, reason: 'цепочка осталась одной строкой');
    expect(selected, '/home/src/main/java');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(selected, '/home');
  });

  testWidgets('строка как в дереве панели: значок объекта и тот же шаг вглубь', (tester) async {
    // Давняя разница: в окне вместо значка стоял один шеврон, а у файла — глиф
    // «файл» на его месте, и имя начиналось не там, где в панели.
    await pump(tester, compact: false);
    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();

    // Home, src, one, x.json и top.json — у каждой строки свой значок.
    expect(find.byType(FileTypeIcon), findsNWidgets(5));

    final metrics = FcTheme.of(tester.element(find.byType(FcDirectoryTree))).metrics;
    final step = FileIconSize.of(metrics, null) + metrics.treeMarkGap;
    final one = tester.getTopLeft(find.text('one')).dx;
    final inside = tester.getTopLeft(find.text('x.json')).dx;
    expect(inside - one, closeTo(step, 0.01));
  });
}
