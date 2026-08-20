import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Показ файла: заголовок, ленивая отрисовка и перенос строк.
void main() {
  late InMemoryContentProvider disk;

  setUp(() {
    disk = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1234)]);
  });

  Future<FsNode> node() async => (await disk.resolvePath('/home/notes.txt').result)!;

  Future<ViewerScreen> screenWith(String text, {bool wordWrap = false}) async => ViewerScreen(
    node: await node(),
    document: TextDocument.parse(text),
    // Без подсветки: этот тест про показ, а не про разбор синтаксиса.
    highlighterFor: (colors) => const PlainHighlighter(),
    wordWrap: wordWrap,
  );

  Future<void> pump(WidgetTester tester, ViewerScreen screen) async {
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

  testWidgets('заголовок называет полный адрес и размер', (tester) async {
    await pump(tester, await screenWith('раз\nдва'));

    // Полный адрес, а не одно имя: файл может лежать в архиве или на сервере.
    expect(find.text('/home/notes.txt'), findsOneWidget);
    expect(find.text('1.2 KB'), findsOneWidget);
  });

  testWidgets('рисуются только видимые строки, а не весь файл', (tester) async {
    final text = List.generate(5000, (i) => 'строка $i').join('\n');

    await pump(tester, await screenWith(text));

    // Пять тысяч строк — и горстка виджетов: список строит то, что видно,
    // плюс небольшой запас.
    final built = tester.widgetList(find.byType(Text)).length;
    expect(built, lessThan(100), reason: 'построено виджетов: $built');
    expect(find.text('строка 0'), findsOneWidget);
    expect(find.text('строка 4999'), findsNothing);
  });

  testWidgets('без переноса файл возят и по ширине', (tester) async {
    await pump(tester, await screenWith('очень длинная строка ${'—' * 300}'));

    final scrolls = tester.widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scrolls.where((view) => view.scrollDirection == Axis.horizontal), hasLength(1));
  });

  testWidgets('с переносом горизонтальной прокрутки нет', (tester) async {
    await pump(tester, await screenWith('очень длинная строка ${'—' * 300}', wordWrap: true));

    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('переключение переноса перерисовывает показ', (tester) async {
    final screen = await screenWith('очень длинная строка ${'—' * 300}');
    await pump(tester, screen);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    screen.toggleWordWrap();
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('стрелки и страницы двигают показ, а Home возвращает в начало', (tester) async {
    final screen = await screenWith(List.generate(500, (i) => 'строка $i').join('\n'));
    await pump(tester, screen);

    // Прокрутка — команды экрана, а не фокус: вид отзывается на просьбу.
    screen.scroll(ScrollStep.lineDown);
    await tester.pumpAndSettle();
    expect(find.text('строка 0'), findsNothing);

    screen.scroll(ScrollStep.pageDown);
    await tester.pumpAndSettle();
    final afterPage = find.textContaining('строка ');
    expect(afterPage, findsWidgets);

    screen.scroll(ScrollStep.toStart);
    await tester.pumpAndSettle();
    expect(find.text('строка 0'), findsOneWidget);

    screen.scroll(ScrollStep.toEnd);
    await tester.pumpAndSettle();
    expect(find.text('строка 499'), findsOneWidget);
  });

  testWidgets('вбок показ двигается только без переноса', (tester) async {
    final screen = await screenWith('первая ${'—' * 500}\nвторая');
    await pump(tester, screen);

    screen.scroll(ScrollStep.columnRight);
    await tester.pumpAndSettle();
    // Начало строки уехало за левый край: значит холст поехал вбок.
    final horizontal = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(horizontal.controller!.offset, greaterThan(0));

    screen.toggleWordWrap();
    await tester.pumpAndSettle();
    // С переносом двигать вбок нечего — и вид не падает от просьбы.
    screen.scroll(ScrollStep.columnRight);
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('пустой файл показывается пустым, а не ломается', (tester) async {
    await pump(tester, await screenWith(''));

    expect(find.text('/home/notes.txt'), findsOneWidget);
  });
}
