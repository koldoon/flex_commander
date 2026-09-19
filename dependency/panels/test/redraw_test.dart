import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Перерисовка по делу (`docs/spec/panel-redraw.md`).
///
/// Сторож, а не замер: он не про миллисекунды, а про то, что шаг курсора
/// пересобирает **две строки** — ту, с которой курсор ушёл, и ту, на которую
/// встал, — а не весь список в обеих панелях.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      for (var i = 0; i < 200; i++) FakeEntry.file('/home/file-${i.toString().padLeft(3, '0')}.txt', size: 100 + i),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    runtime = await testApp(provider: provider, modules: featureModules(), settings: settings);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  /// Сколько раз каркас пересобрал каждый виджет, пока шло [action].
  ///
  /// Считается перехватом `debugPrint`: при `debugPrintRebuildDirtyWidgets`
  /// каркас сам называет каждый пересобранный элемент. Своих счётчиков ради
  /// этого в рисующий код заводить не нужно.
  Future<Map<String, int>> rebuilds(WidgetTester tester, Future<void> Function() action) async {
    final counts = <String, int>{};
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null || !(message.startsWith('Rebuilding ') || message.startsWith('Building '))) {
        return;
      }
      final name = message.split(' ').skip(1).join(' ').split(RegExp('[-(]')).first.trim();
      counts[name] = (counts[name] ?? 0) + 1;
    };
    debugPrintRebuildDirtyWidgets = true;
    await action();
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = original;
    return counts;
  }

  testWidgets('шаг курсора пересобирает две строки, а не весь список', (tester) async {
    await pumpApp(tester);
    final shown = tester.widgetList(find.byType(FileTableRow)).length;
    expect(shown, greaterThan(20), reason: 'проверять нечего: строк на экране слишком мало');

    final counts = await rebuilds(tester, () async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    });

    // Две: та, с которой курсор ушёл, и та, на которую встал. Соседняя панель
    // не пересобирается вовсе — её строки в этот счёт не попадают.
    expect(
      counts['FileTableRow'] ?? 0,
      lessThanOrEqualTo(2),
      reason: 'пересобран весь список (на экране $shown строк): ${counts['FileTableRow']}',
    );
  });

  testWidgets('пометка перерисовывает свою строку', (tester) async {
    await pumpApp(tester);
    // Уходим с «..»: он не помечается никогда, и проверять было бы нечего.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    final counts = await rebuilds(tester, () async {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
    });

    expect(runtime.app.left.markedPaths, isNotEmpty, reason: 'пометка не поставилась — проверять нечего');
    // Пометка и шаг курсора — одно действие, поэтому строк тут больше одной,
    // но всё так же единицы, а не весь список.
    expect(counts['FileTableRow'] ?? 0, greaterThan(0), reason: 'помеченная строка не перерисовалась');
    expect(counts['FileTableRow'] ?? 0, lessThanOrEqualTo(4));
  });

  testWidgets('перестановка сортировкой собирает строки заново', (tester) async {
    await pumpApp(tester);
    final before =
        tester.widgetList<FileTableRow>(find.byType(FileTableRow)).map((row) => row.entry.name).take(5).toList();

    runtime.app.left.sortBy(FsColumns.name);
    await tester.pumpAndSettle();

    final after =
        tester.widgetList<FileTableRow>(find.byType(FileTableRow)).map((row) => row.entry.name).take(5).toList();
    expect(after, isNot(before), reason: 'память строк отдала прежние строки после перестановки');
  });

  testWidgets('панель сузили — строки собраны по новым ширинам', (tester) async {
    await pumpApp(tester);
    final before = tester.getSize(find.byType(FileTableRow).first).width;

    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();

    // Ширины входят в приметы кадра вместе с темой и раскладкой: кешированная
    // строка размечена прежними, и отдать её значило бы показать неправду.
    expect(tester.getSize(find.byType(FileTableRow).first).width, lessThan(before));
  });
}
