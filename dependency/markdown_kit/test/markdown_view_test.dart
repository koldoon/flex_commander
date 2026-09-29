import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Рисовальщик врезки для теста: что объявил, то и делает.
MarkdownBlockSpec _spec(
  String id, {
  String language = 'mermaid',
  int priority = 0,
  Widget Function(BuildContext, MarkdownBlockRequest)? build,
}) => MarkdownBlockSpec(
  id: id,
  title: 'Block $id',
  priority: priority,
  accepts: (name) => name == language,
  build: build ?? (context, request) => Text('нарисовал $id: ${request.source}'),
);

/// Показ markdown: вёрстка, ленивость и дисциплина врезок.
void main() {
  Future<void> pump(
    WidgetTester tester,
    String source, {
    List<MarkdownBlockSpec> blocks = const [],
    void Function(String text, String? href, String title)? onTapLink,
    Size size = const Size(600, 400),
    EdgeInsets contentPadding = EdgeInsets.zero,
    double contentWidthFactor = 1,
    double headingSpacing = 0,
    bool autofocus = false,
    int? startAtBlock,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: FcMarkdownView(
                document: FcMarkdownDocument.parse(source),
                blocks: blocks,
                onTapLink: onTapLink,
                contentPadding: contentPadding,
                contentWidthFactor: contentWidthFactor,
                headingSpacing: headingSpacing,
                autofocus: autofocus,
                startAtBlock: startAtBlock,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('вёрстка', () {
    testWidgets('заголовок и абзац показаны текстом, а не разметкой', (tester) async {
      await pump(tester, '# Заголовок\n\nПросто абзац.\n');

      expect(find.text('Заголовок'), findsOneWidget);
      expect(find.text('Просто абзац.'), findsOneWidget);
      expect(find.textContaining('#'), findsNothing);
    });

    testWidgets('в таблице текст прижат влево и вверх', (tester) async {
      // У правой ячейки три строки, у левой одна: по середине высоты они
      // разъехались бы.
      await pump(
        tester,
        '| Ключ | Что делает |\n|---|---|\n| `F3` | раз<br/>два<br/>три |\n',
        size: const Size(800, 400),
      );

      final head = tester.getRect(find.text('Ключ'));
      final cell = tester.getRect(find.textContaining('F3'));
      final tall = tester.getRect(find.textContaining('раз'));

      expect((cell.left - head.left).abs(), lessThan(2), reason: 'заголовок и ячейка — по одному левому краю');
      expect((cell.top - tall.top).abs(), lessThan(2), reason: 'обе ячейки начинаются с верхней кромки строки');
    });

    testWidgets('цитата, таблица и эмодзи показываются', (tester) async {
      await pump(tester, '> Осторожно.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nГотово :tada:\n');

      expect(find.textContaining('Осторожно.'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('🎉'), findsOneWidget);
    });

    testWidgets('врезка GitHub не роняет показ', (tester) async {
      // Она разбирается обычной цитатой: правило, делавшее из неё `div`, в
      // набор не входит — на нём отрисовка падала.
      await pump(tester, '> [!NOTE]\n> Осторожно.\n');

      expect(find.textContaining('Осторожно.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('врезки', () {
    testWidgets('никто не объявлен — врезка остаётся врезкой кода', (tester) async {
      await pump(tester, '```dart\nvoid main() {}\n```\n');

      expect(find.byType(FcCodeBlock), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
    });

    testWidgets('объявленный рисовальщик берётся за свой язык', (tester) async {
      await pump(tester, '```mermaid\nA-->B\n```\n', blocks: [_spec('mermaid')]);

      expect(find.text('нарисовал mermaid: A-->B'), findsOneWidget);
      expect(find.byType(FcCodeBlock), findsNothing);
    });

    testWidgets('чужой язык он не трогает', (tester) async {
      await pump(tester, '```dart\nvoid main() {}\n```\n', blocks: [_spec('mermaid')]);

      expect(find.byType(FcCodeBlock), findsOneWidget);
    });

    testWidgets('«не мой язык» — спрашивают следующего', (tester) async {
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [
          _spec('first', priority: 10, build: (context, request) => throw const MarkdownBlockDeclined()),
          _spec('second'),
        ],
      );

      expect(find.text('нарисовал second: A-->B'), findsOneWidget);
    });

    testWidgets('«взялся и не смог» — виден исходник и причина', (tester) async {
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [_spec('mermaid', build: (context, request) => throw const MarkdownBlockRefused('Строка 1: не понял'))],
      );

      expect(find.text('Строка 1: не понял'), findsOneWidget);
      expect(find.textContaining('A-->B'), findsOneWidget);
    });

    testWidgets('чужая ошибка не уносит документ', (tester) async {
      await pump(
        tester,
        '# Заголовок\n\n```mermaid\nA-->B\n```\n\nХвост.\n',
        blocks: [_spec('mermaid', build: (context, request) => throw StateError('сломался'))],
      );

      // Документ цел, врезка стала текстом с объяснением.
      expect(find.text('Заголовок'), findsOneWidget);
      expect(find.text('Хвост.'), findsOneWidget);
      expect(find.text('This block could not be drawn'), findsOneWidget);
      expect(find.textContaining('A-->B'), findsOneWidget);
    });

    testWidgets('ширина доезжает до рисовальщика', (tester) async {
      late double given;
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [
          _spec(
            'mermaid',
            build: (context, request) {
              given = request.maxWidth;
              return const SizedBox.shrink();
            },
          ),
        ],
        size: const Size(480, 300),
      );

      expect(given, greaterThan(0), reason: 'диаграмме нужна ширина до раскладки');
      expect(given, lessThanOrEqualTo(480));
    });
  });

  group('ленивость', () {
    testWidgets('далёкий блок не строится, пока до него не долистали', (tester) async {
      final source = [for (var i = 0; i < 300; i++) 'Блок номер $i.'].join('\n\n');

      await pump(tester, source, size: const Size(400, 200));

      expect(find.text('Блок номер 0.'), findsOneWidget);
      expect(
        find.text('Блок номер 299.'),
        findsNothing,
        reason: 'весь документ разом — это тысячи виджетов до первого кадра',
      );
    });

    testWidgets('долистали — построился', (tester) async {
      final source = [for (var i = 0; i < 300; i++) 'Блок номер $i.'].join('\n\n');

      await pump(tester, source, size: const Size(400, 200));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();

      expect(find.text('Блок номер 0.'), findsNothing);
      expect(find.textContaining('Блок номер'), findsWidgets);
    });
  });

  group('документ, а не сплошной текст', () {
    testWidgets('колонка уже области: строка во всю ширину читается плохо', (tester) async {
      late double given;
      await pump(
        tester,
        '```mermaid\nA-->B\n```\n',
        blocks: [
          _spec(
            'mermaid',
            build: (context, request) {
              given = request.maxWidth;

              return const SizedBox.shrink();
            },
          ),
        ],
        size: const Size(800, 300),
        contentWidthFactor: 0.75,
      );

      // Три четверти от восьмисот. Врезке достаётся ширина **колонки**, а не
      // области: иначе диаграмма вылезла бы за поля.
      expect(given, 600);
    });

    testWidgets('текст стоит не у самой кромки', (tester) async {
      await pump(tester, 'Первый абзац.\n', size: const Size(800, 300), contentWidthFactor: 0.75);

      final box = tester.getRect(find.text('Первый абзац.'));
      final list = tester.getRect(find.byType(CustomScrollView));

      expect(box.left - list.left, greaterThan(90), reason: 'слева поле в восьмую часть ширины');
      expect(list.right - box.right, greaterThan(90));
    });

    testWidgets('поле сверху отодвигает документ от кромки', (tester) async {
      await pump(
        tester,
        'Первый абзац.\n',
        size: const Size(800, 300),
        contentPadding: const EdgeInsets.symmetric(vertical: 50),
      );

      final list = tester.getRect(find.byType(CustomScrollView));
      final text = tester.getRect(find.text('Первый абзац.'));

      expect(text.top - list.top, greaterThanOrEqualTo(50));
    });

    testWidgets('над чертой воздуха больше, чем между абзацами', (tester) async {
      // Вплотную к предыдущему абзацу черта читается его подчёркиванием, а не
      // границей частей.
      await pump(
        tester,
        'Конец части.\n\nВторой абзац.\n\n---\n\nНовая часть.\n',
        size: const Size(800, 400),
        headingSpacing: 32,
      );

      final double withGap =
          tester.getRect(find.text('Новая часть.')).top - tester.getRect(find.text('Второй абзац.')).bottom;

      // Тот же документ без отбивки: заголовков в нём нет, и больше `headingSpacing`
      // влиять не на что — вся разница приходится на черту.
      await pump(tester, 'Конец части.\n\nВторой абзац.\n\n---\n\nНовая часть.\n', size: const Size(800, 400));

      final double without =
          tester.getRect(find.text('Новая часть.')).top - tester.getRect(find.text('Второй абзац.')).bottom;

      expect(withGap - without, moreOrLessEquals(32 * 0.4, epsilon: 0.5));
    });

    testWidgets('над заголовком воздуха больше, чем между абзацами', (tester) async {
      await pump(
        tester,
        'Конец раздела.\n\n## Новый раздел\n\nЕго текст.\n',
        size: const Size(800, 400),
        headingSpacing: 32,
      );

      final before = tester.getRect(find.text('Конец раздела.'));
      final heading = tester.getRect(find.text('Новый раздел'));
      final after = tester.getRect(find.text('Его текст.'));

      // Заголовок принадлежит тому, что под ним: сверху отбивка больше.
      expect(heading.top - before.bottom, greaterThan(after.top - heading.bottom));
      expect(heading.top - before.bottom, greaterThanOrEqualTo(32));
    });

    testWidgets('подзаголовку воздуха меньше, чем разделу', (tester) async {
      await pump(
        tester,
        'Текст.\n\n## Раздел\n\nТекст.\n\n#### Мелкий\n\nТекст.\n',
        size: const Size(800, 600),
        headingSpacing: 32,
      );

      final texts = find.text('Текст.');
      final big = tester.getRect(find.text('Раздел'));
      final small = tester.getRect(find.text('Мелкий'));

      final beforeBig = big.top - tester.getRect(texts.at(0)).bottom;
      final beforeSmall = small.top - tester.getRect(texts.at(1)).bottom;

      expect(beforeSmall, lessThan(beforeBig), reason: 'часть и подраздел должны различаться, не читая');
    });

    testWidgets('первому блоку отбивка не нужна: над ним и так поле', (tester) async {
      await pump(tester, '# Заголовок\n\nТекст.\n', size: const Size(800, 400), headingSpacing: 32);

      final list = tester.getRect(find.byType(CustomScrollView));
      final heading = tester.getRect(find.text('Заголовок'));

      expect(heading.top - list.top, lessThan(32));
    });

    testWidgets('без доводов всё как было: полная ширина и без полей', (tester) async {
      await pump(tester, 'Первый абзац.\n', size: const Size(800, 300));

      final box = tester.getRect(find.text('Первый абзац.'));
      final list = tester.getRect(find.byType(CustomScrollView));

      expect(box.left - list.left, lessThan(10));
      expect(box.top - list.top, lessThan(10));
    });
  });

  group('прокрутка клавишами', () {
    /// Длинный документ: коротким листать нечего.
    String longDocument() => [for (var i = 0; i < 200; i++) 'Строка номер $i.'].join('\n\n');

    double offsetOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

    testWidgets('стрелка вниз листает, вверх возвращает', (tester) async {
      await pump(tester, longDocument(), size: const Size(500, 300), autofocus: true);
      expect(offsetOf(tester), 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final stepped = offsetOf(tester);
      expect(stepped, greaterThan(0), reason: 'нажатие обязано что-то менять');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(offsetOf(tester), lessThan(stepped));
    });

    testWidgets('страница листает больше строки', (tester) async {
      await pump(tester, longDocument(), size: const Size(500, 300), autofocus: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final line = offsetOf(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();

      expect(offsetOf(tester), greaterThan(line));
    });

    /// Документ, на котором предел прокрутки **занижен**: сверху короткие
    /// абзацы, а вся высота — во врезках в конце.
    ///
    /// Ленивый список считает предел по средней высоте построенного, и пока
    /// построены одни короткие абзацы, конец документа кажется гораздо ближе,
    /// чем он есть. Завышенный предел Flutter поправляет сам, заниженный — нет:
    /// прыжок в него упирается в никуда.
    String taperedDocument() {
      final tall = '```\n${List.generate(80, (n) => 'строка кода $n').join('\n')}\n```';

      return [
        for (var i = 0; i < 200; i++) 'Абзац $i.',
        for (var i = 0; i < 20; i++) tall,
        'Самый последний абзац.',
      ].join('\n\n');
    }

    ScrollPosition positionOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('`End` доводит до последнего блока, а не куда придётся', (tester) async {
      await pump(tester, taperedDocument(), size: const Size(500, 300), autofocus: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();

      // Проверяем не «уехали куда-то», а «виден конец»: прежняя проверка
      // требовала от `End` только «больше нуля» — и пропускала ровно эту беду.
      expect(find.text('Самый последний абзац.'), findsOneWidget);
      expect(positionOf(tester).pixels, moreOrLessEquals(positionOf(tester).maxScrollExtent, epsilon: 0.5));
    });

    testWidgets('`Home` возвращает к первому блоку', (tester) async {
      await pump(tester, taperedDocument(), size: const Size(500, 300), autofocus: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();

      expect(find.text('Абзац 0.'), findsOneWidget);
      expect(positionOf(tester).pixels, positionOf(tester).minScrollExtent);
    });

    testWidgets('`End` доводит до конца и из середины документа', (tester) async {
      // Открыли с середины — предел занижен ещё сильнее: построена только
      // середина, а хвост целиком во врезках.
      await pump(tester, taperedDocument(), size: const Size(500, 300), autofocus: true, startAtBlock: 100);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();

      expect(find.text('Самый последний абзац.'), findsOneWidget);
    });

    testWidgets('`Home` доходит до начала и из середины документа', (tester) async {
      await pump(tester, taperedDocument(), size: const Size(500, 300), autofocus: true, startAtBlock: 100);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();

      expect(find.text('Абзац 0.'), findsOneWidget);
    });

    testWidgets('дальше краёв не уезжает', (tester) async {
      await pump(tester, longDocument(), size: const Size(500, 300), autofocus: true);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(offsetOf(tester), 0, reason: 'выше начала листать некуда');
    });
  });

  group('ссылки', () {
    testWidgets('нажатие уходит наружу', (tester) async {
      String? tapped;
      await pump(
        tester,
        'Читайте [документацию](https://example.org).\n',
        onTapLink: (text, href, title) {
          tapped = href;
        },
      );

      await tester.tap(find.textContaining('документацию'));
      await tester.pump();

      expect(tapped, 'https://example.org');
    });
  });

  group('список задач', () {
    const source = '- [ ] не сделано\n- [x] сделано\n- [ ] тоже не сделано\n';

    testWidgets('флажки — наши, а не значки Material', (tester) async {
      // Значок Material рисуется чёрным и в тёмной теме выглядит дырой.
      await pump(tester, source);

      expect(find.byType(FcCheckboxMark), findsNWidgets(3));
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
    });

    testWidgets('флажок квадратный, а не растянутый', (tester) async {
      // Показ ставит значок пункта в коробку жёсткой ширины, и без `Align`
      // флажок растягивается поперёк неё. На глаз это видно плохо — поэтому
      // меряем, а не смотрим.
      await pump(tester, source);

      final theme = FcTheme(
        colors: DefaultColors(),
        metrics: DefaultMetrics(),
        icons: DefaultIcons(),
        fonts: DefaultFonts(),
      );
      final size = tester.getSize(find.byType(FcCheckboxMark).first);

      expect(size.width, theme.metrics.checkboxSize);
      expect(size.height, theme.metrics.checkboxSize);
    });

    testWidgets('флажок стоит там же, где маркер обычного списка', (tester) async {
      // Флажок — это маркер списка задач. Прижатый влево, он один торчал бы за
      // поля документа: `•` показ центрует в колонке маркера, а номер и вовсе
      // прижимает вправо.
      await pump(tester, '- обычный пункт\n');
      final bullet = tester.getRect(find.text('•')).center.dx;

      await pump(tester, source);
      final mark = tester.getRect(find.byType(FcCheckboxMark).first).center.dx;

      expect(mark, moreOrLessEquals(bullet, epsilon: 1));
    });

    testWidgets('отмеченное отмечено, неотмеченное нет', (tester) async {
      await pump(tester, source);

      final marks = tester.widgetList<FcCheckboxMark>(find.byType(FcCheckboxMark));

      expect(marks.map((mark) => mark.value), [false, true, false]);
    });

    testWidgets('нажатие ничего не меняет: документ показывают, а не правят', (tester) async {
      await pump(tester, source);

      await tester.tap(find.byType(FcCheckboxMark).first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.widgetList<FcCheckboxMark>(find.byType(FcCheckboxMark)).map((mark) => mark.value), [
        false,
        true,
        false,
      ]);
    });
  });
}
