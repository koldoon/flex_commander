import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Строка состояния договаривает длинное имя, вырастая на вторую и третью
/// строчку, — если ей это позволено настройкой
/// (`docs/widgets.md`, раздел `PanelStatusBar`; `docs/spec/panel-status-lines.md`).
void main() {
  const short = 'notes.txt';
  const long =
      'невероятно длинное имя файла, которое в одну строку не помещается никак и '
      'требует от строки состояния второй строчки.txt';
  const huge =
      'имя, которое не влезет и в три строчки: оно длиннее всего, что человек станет '
      'называть именем файла, и нужно оно здесь ровно затем, чтобы проверить предел роста — '
      'дальше многоточие, потому что иначе полоса съела бы половину списка, а список важнее.txt';

  /// Ссылка с длинными обоими концами: в одну строчку не влезает никак.
  const link = 'ссылка на что-то очень далёкое и с длинным именем.lnk';
  const target = '/Users/koldoon/Developer/Projects/каталог с длинным именем/цель ссылки.txt';

  late AppRuntime runtime;

  /// Полоса растёт, только если ей позволено: умолчание — одна строчка, а эти
  /// проверки про рост, поэтому они его и просят.
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1000, 600),
    int lines = PanelsSettings.maxStatusLines,
  }) async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/$short', size: 10),
        FakeEntry.file('/home/$long', size: 20),
        FakeEntry.file('/home/$huge', size: 30),
        FakeEntry.link('/home/$link', target),
      ])..home = '/home',
      modules: featureModules(),
    );
    runtime.app.moduleSettings('fc.panels').section(PanelsSettings.new).statusLines = lines;
    await runtime.app.start();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  /// Высота полосы под активной панелью.
  double statusHeight(WidgetTester tester) => tester.getSize(find.byType(PanelStatusBar).first).height;

  Future<double> heightOn(WidgetTester tester, String name) async {
    runtime.app.left.setCursorToName(name);
    await tester.pumpAndSettle();
    return statusHeight(tester);
  }

  testWidgets('короткое имя — полоса прежней высоты', (tester) async {
    await open(tester);

    expect(await heightOn(tester, short), const DefaultMetrics().statusBarHeight);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('поля сверху и снизу те же, что были у однострочной', (tester) async {
    await open(tester);

    // Однострочный случай: текст стоит ровно посередине полосы — так его
    // держала её собственная высота, и правка не вправе это сдвинуть.
    await heightOn(tester, short);
    final bar = tester.getRect(find.byType(PanelStatusBar).first);
    final text = tester.getRect(
      find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)).first,
    );

    expect(text.top - bar.top - const DefaultMetrics().strokeWidth, closeTo(bar.bottom - text.bottom, 0.5));

    // Выросшая полоса — те же поля сверху и снизу.
    await heightOn(tester, long);
    final tall = tester.getRect(find.byType(PanelStatusBar).first);
    final lines = tester.getRect(
      find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)).first,
    );

    expect(lines.top - tall.top - const DefaultMetrics().strokeWidth, closeTo(tall.bottom - lines.bottom, 0.5));
    expect(tall.bottom - lines.bottom, greaterThan(0), reason: 'текст не упирается в рамку');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('длинное имя — полоса выросла, и имя видно целиком', (tester) async {
    await open(tester);
    final one = await heightOn(tester, short);
    final many = await heightOn(tester, long);

    expect(many, greaterThan(one), reason: 'договаривать имя под курсором больше некому');

    final shown = tester.widget<Text>(
      find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)).first,
    );
    expect(shown.textSpan!.toPlainText(), long, reason: 'целиком, а не обрезанное');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('выше трёх строчек полоса не растёт', (tester) async {
    await open(tester);
    final two = await heightOn(tester, long);
    final capped = await heightOn(tester, huge);

    expect(capped, greaterThanOrEqualTo(two));
    // Три строки плюс линейка сверху: четвёртая отъедала бы от списка заметно.
    final line = capped - const DefaultMetrics().strokeWidth;
    expect(line / PanelsSettings.maxStatusLines, lessThan(const DefaultMetrics().statusBarHeight));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('по умолчанию полоса в одну строчку и не растёт вовсе', (tester) async {
    await open(tester, lines: PanelsSettings.defaultStatusLines);

    final one = await heightOn(tester, short);
    final onLong = await heightOn(tester, long);

    expect(onLong, one, reason: 'дёрганье списка человек видит каждый раз, а длинное имя — изредка');
    expect(one, const DefaultMetrics().statusBarHeight);

    // Недоговорённое договаривает подсказка — правило то же, что и было.
    final tip = find.ancestor(
      of: find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)).first,
      matching: find.byType(FcTooltip),
    );
    expect(tip, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('выбрана середина — полоса режет серединой', (tester) async {
    await open(tester, lines: PanelsSettings.defaultStatusLines);
    runtime.app.moduleSettings('fc.panels').section(PanelsSettings.new).nameTrim = PanelsSettings.trimMiddle;
    await heightOn(tester, long);

    final shown = tester.widget<Text>(
      find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)).first,
    );
    final text = shown.textSpan!.toPlainText();

    expect(text, isNot(long), reason: 'целиком оно не влезло');
    expect(text, contains('…'));
    expect(text, endsWith('.txt'), reason: 'то же правило, что и в колонке: хвост на виду');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('у ссылки стрелка переживает обрезку серединой', (tester) async {
    await open(tester, lines: PanelsSettings.defaultStatusLines);
    runtime.app.moduleSettings('fc.panels').section(PanelsSettings.new).nameTrim = PanelsSettings.trimMiddle;
    await heightOn(tester, link);

    final shown = tester.widget<Text>(
      find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)).first,
    );
    final text = shown.textSpan!.toPlainText();

    expect(text, startsWith('ссылка'));
    expect(text, endsWith('.txt'), reason: 'цель ссылки — самое нужное в этой строке');
    // Без стрелки строка читалась бы как одно длинное имя, а не как ссылка.
    expect('…'.allMatches(text).length, 2, reason: 'разрез обошёл стрелку с обеих сторон');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('курсор остаётся виден, когда полоса выросла', (tester) async {
    // Окно тесное нарочно: курсор стоит у нижнего края, и рост полосы
    // вытолкнул бы его под обрез.
    await open(tester, size: const Size(900, 300));

    runtime.app.left.setCursorToName(huge);
    await tester.pumpAndSettle();

    // Панели две и стоят на одном каталоге — ищем в левой.
    final row = find.descendant(
      of: find.byType(FileTable).first,
      matching: find.byWidgetPredicate((widget) => widget is FileTableRow && widget.entry.name == huge),
    );
    expect(row, findsOneWidget, reason: 'строка под курсором осталась на экране');

    final bottom = tester.getRect(row).bottom;
    final status = tester.getRect(find.byType(PanelStatusBar).first).top;
    expect(bottom, lessThanOrEqualTo(status + 1), reason: 'и не заехала под полосу');

    await tester.pump(const Duration(milliseconds: 20));
  });
}
