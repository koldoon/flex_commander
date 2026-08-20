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

  testWidgets('заголовок — та же плашка, что у панели, с адресом и размером', (tester) async {
    await pump(tester, await screenWith('раз\nдва'));

    // Одна плашка на всё: рамку и заголовок просмотрщик берёт у общего
    // `FcPanelFrame` — того же, которым рисуется файловая панель.
    expect(find.byType(FcPanelFrame), findsOneWidget);
    final plate = tester.widget<FcPathPlate>(find.byType(FcPathPlate));

    // Полный адрес, а не одно имя: файл может лежать в архиве или на сервере.
    expect(plate.path, '/home/notes.txt');
    expect(plate.trailing, '1.2 KB');
    expect(find.text('/home/notes.txt'), findsOneWidget);
  });

  testWidgets('плашка облегает содержимое, а не тянется на всю ширину', (tester) async {
    await pump(tester, await screenWith('раз'));

    final plate = tester.getRect(find.byType(FcPathPlate));
    final frame = tester.getRect(find.byType(FcPanelFrame));

    expect(plate.width, lessThan(frame.width / 2));
    // И наполовину заходит на верхнюю рамку — как у панели.
    expect(plate.top, frame.top);
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

  testWidgets('у узкого файла полоса прокрутки прижата к краю окна', (tester) async {
    // Длинный, но узкий файл: вертикальная прокрутка нужна, а горизонтальная
    // нет. Полоса должна стоять по краю окна, а не по краю текста — иначе она
    // висит посреди пустого места.
    final screen = await screenWith(List.generate(500, (i) => 'ы').join('\n'));
    await pump(tester, screen);

    final listWidth = tester.getSize(find.byType(ListView)).width;
    final available = tester.getSize(find.byType(Scrollbar).first).width;

    expect(listWidth, available, reason: 'холст сузился по тексту');
  });

  testWidgets('полосы стоят по краю панели, а показываются как везде', (tester) async {
    final inset = DefaultMetrics().scrollbarInset;
    final screen = await screenWith(List.generate(500, (i) => 'строка $i').join('\n'));
    await pump(tester, screen);

    final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar)).toList();
    expect(bars, hasLength(2));
    // Показываются так же, как в файловых панелях, — поведением прокрутки по
    // умолчанию. Своей видимостью просмотрщик не выделяется.
    expect(bars.every((bar) => bar.thumbVisibility == null), isTrue);

    final panel = tester.getRect(
      find.ancestor(of: find.byType(Scrollbar).first, matching: find.byType(DecoratedBox)).first,
    );
    final bar = tester.getRect(find.byType(Scrollbar).first);

    // Справа рамки нет вовсе: просмотрщик во всю ширину окна, оба края у него
    // внешние — как у панелей, прижатых к краям.
    expect(bar.right, panel.right - inset);
    // Снизу рамка есть, и полоса стоит внутри неё.
    expect(bar.bottom, panel.bottom - const DefaultMetrics().strokeWidth - inset);
    // Сверху между рамкой и содержимым стоит поле панели — полоса начинается
    // за ним, как и текст.
    expect(bar.top, greaterThan(panel.top));
  });

  testWidgets('поля текста полосы от рамки не отодвигают', (tester) async {
    final inset = DefaultMetrics().scrollbarInset;
    await pump(tester, await screenWith(List.generate(500, (i) => 'строка $i').join('\n')));

    final panel = tester.getRect(
      find.ancestor(of: find.byType(Scrollbar).first, matching: find.byType(DecoratedBox)).first,
    );
    final text = tester.getRect(find.text('строка 0').first);

    // Текст отодвинут своими полями — заметно дальше, чем полоса.
    expect(text.left, greaterThan(panel.left + inset * 2));
  });

  testWidgets('широкий файл по-прежнему шире окна', (tester) async {
    final screen = await screenWith('первая ${'—' * 500}\nвторая');
    await pump(tester, screen);

    final listWidth = tester.getSize(find.byType(ListView)).width;
    final available = tester.getSize(find.byType(Scrollbar).first).width;

    // Растягивание до края не должно отнимать горизонтальную прокрутку.
    expect(listWidth, greaterThan(available));
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

    double offset() => tester.widget<ListView>(find.byType(ListView)).controller!.offset;

    // Прокрутка — команды экрана, а не фокус: вид отзывается на просьбу.
    screen.scroll(ScrollStep.lineDown);
    await tester.pumpAndSettle();
    final afterLine = offset();
    expect(afterLine, greaterThan(0));

    screen.scroll(ScrollStep.pageDown);
    await tester.pumpAndSettle();
    // Страница двигает заметно дальше строки.
    expect(offset(), greaterThan(afterLine * 5));

    screen.scroll(ScrollStep.toStart);
    await tester.pumpAndSettle();
    expect(offset(), 0);
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
