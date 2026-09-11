import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль со своей колонкой — обеими половинами, как и положено.
///
/// Метка: первая буква имени. Смысла в ней нет никакого, зато видно и в
/// строке, и в порядке.
class _Marks implements FcBackendModule, FcFrontendModule {
  const _Marks();

  static const String columnId = 'test.mark';

  static const ColumnSpec spec = ColumnSpec(id: columnId, title: 'Mark', width: 40, visible: false);

  @override
  String get id => 'test.marks';

  @override
  String get title => 'Marks';

  @override
  void installBackend(BackendRegistry registry) {
    registry.column(spec, compare: (_) => (a, b) => _markOf(a.name).compareTo(_markOf(b.name)));
  }

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.column(spec, text: (cell) => _markOf(cell.entry.name));
  }

  static String _markOf(String name) => name.isEmpty ? '' : name.substring(0, 1).toUpperCase();
}

void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/apple.txt', size: 300),
      FakeEntry.file('/home/cherry.txt', size: 100),
      FakeEntry.file('/home/banana.txt', size: 200),
    ]);
  });

  Future<AppRuntime> start(WidgetTester tester, {List<FcModule> modules = const []}) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    final runtime = await testApp(provider: provider, modules: [...featureModules(), ...modules], settings: settings);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Флажок колонки в окне выбора вида левой панели.
  Future<void> openViewDialog(AppRuntime runtime, WidgetTester tester) async {
    runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
    await tester.pumpAndSettle();
  }

  group('колонка модуля', () {
    testWidgets('объявленная модулем колонка доходит до меню видимости и до строк', (tester) async {
      final runtime = await start(tester, modules: [const _Marks()]);
      final app = runtime.app;

      // Объявлена, но спрятана: включает её человек.
      expect(app.columns.find(_Marks.columnId)?.title, 'Mark');
      expect(app.left.columns.find(_Marks.columnId)?.visible, isFalse);

      await openViewDialog(runtime, tester);
      await tester.tap(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Mark')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.columns.find(_Marks.columnId)?.visible, isTrue);
      // Ячейка рисуется тем, что объявил модуль.
      expect(find.descendant(of: find.byType(FileTableRow), matching: find.text('A')), findsOneWidget);
    });

    testWidgets('и сортируется своим сравнением', (tester) async {
      final runtime = await start(tester, modules: [const _Marks()]);
      final app = runtime.app;

      await app.left.sortBy(_Marks.columnId);
      await tester.pumpAndSettle();

      expect(app.left.sort.column, _Marks.columnId);
      expect(app.left.entries.map((entry) => entry.name).skip(1), ['apple.txt', 'banana.txt', 'cherry.txt']);
    });

    testWidgets('без модуля колонка спит, а раскладка цела', (tester) async {
      // Тот же порядок колонок, что человек и настраивал, плюс запись о чужой
      // колонке — модуля, которого в этой сборке нет.
      final saved = ColumnLayout.fromJson([
        {'id': 'icon', 'visible': true},
        {'id': 'name', 'visible': true},
        {'id': _Marks.columnId, 'width': 40, 'visible': true},
        {'id': 'size', 'width': 111, 'visible': true},
      ]);
      final settings = AppSettings(
        left: PanelSettings(path: '/home', columns: saved),
        right: PanelSettings.defaults('/home'),
      );
      final runtime = await testApp(provider: provider, modules: featureModules(), settings: settings);
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();
      final app = runtime.app;

      // Рисовать нечем — и не рисуем.
      expect(app.left.columns.find(_Marks.columnId), isNull);
      // Своё человеческое при этом цело.
      expect(app.left.columns.find('size')?.width, 111);

      // Тронули раскладку — чужая запись обязана вернуться на место.
      await app.left.setColumnLayout(app.left.columns.toggleVisible('attributes'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.core!.settings!.left.columns.find(_Marks.columnId)?.visible, isTrue);
      expect(app.core!.settings!.left.columns.find(_Marks.columnId)?.width, 40);
    });
  });

  test('объявленное на двух сторонах совпадает', () {
    // Объявление регистрируется по разу на каждой стороне, и разъехаться ему
    // негде — но проверить это дешевле, чем однажды искать причину того, что
    // колонка сортируется не так, как нарисована.
    final core = testColumnSorting().declared;
    final screen = testPanelColumns().declared;

    expect(core.map((c) => c.id), screen.map((c) => c.id));
    for (var i = 0; i < core.length; i++) {
      expect(core[i].title, screen[i].title, reason: core[i].id);
      expect(core[i].width, screen[i].width, reason: core[i].id);
      expect(core[i].sortable, screen[i].sortable, reason: core[i].id);
      expect(core[i].pinned, screen[i].pinned, reason: core[i].id);
      expect(core[i].inLayout, screen[i].inLayout, reason: core[i].id);
    }
  });
}
