import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль с подставным видом: приложение о нём ничего не знает заранее — ровно
/// так же, как о будущем дереве и значках.
class _ProbeViews implements FcFrontendModule {
  const _ProbeViews();

  static const String viewId = 'probe';

  @override
  String get id => 'test.views';

  @override
  String get title => 'View probe';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.panelView(
      PanelViewSpec(
        id: viewId,
        title: 'Probe',
        description: 'A view that only a test declares',
        build: (context, panel) => const Text('вид пробы'),
      ),
    );
    registry.binding(
      KeyBinding('Cmd-9', SetPanelViewCommand.commandId, parameters: {SetPanelViewCommand.viewParam: viewId}),
    );
  }
}

/// Виды панели: общая часть механизма.
///
/// Спецификация — `docs/spec/panel-views.md`.
void main() {
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/docs'),
    FakeEntry.file('/home/notes.txt', size: 10),
  ])..home = '/home';

  Future<AppRuntimeAndScreen> open(WidgetTester tester, {AppSettings? settings}) async {
    final runtime = await testApp(
      provider: provider(),
      modules: [...featureModules(), const _ProbeViews()],
      settings: settings,
    );
    await runtime.app.start();

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    return (runtime: runtime, tester: tester);
  }

  testWidgets('каталог рисуется выбранным видом, а незнакомый — таблицей', (tester) async {
    final (:runtime, tester: _) = await open(tester);

    expect(find.byType(FileTable), findsNWidgets(2), reason: 'по умолчанию обе панели таблицей');

    await runtime.app.left.setView(_ProbeViews.viewId);
    await tester.pumpAndSettle();
    expect(find.text('вид пробы'), findsOneWidget);
    expect(find.byType(FileTable), findsOneWidget, reason: 'соседняя панель осталась таблицей');

    // Вид, которого никто не объявлял: имя в настройках такое бывает — модуль
    // выключили. Панель показывает каталог, а не пустоту.
    await runtime.app.left.setView('nobody-declares-this');
    await tester.pumpAndSettle();
    expect(find.byType(FileTable), findsNWidgets(2));
    expect(runtime.app.left.view, 'nobody-declares-this', reason: 'имя из настроек не стёрлось');
  });

  testWidgets('Alt-F1 и Alt-F2 выбирают вид своей панели', (tester) async {
    final (:runtime, tester: _) = await open(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.pumpAndSettle();

    expect(find.byType(FcPickList), findsOneWidget, reason: 'окно выбора открылось');
    // Строка списка — имя и пояснение разом, поэтому по вхождению.
    expect(
      find.textContaining('Probe', findRichText: true),
      findsOneWidget,
      reason: 'вид пробы объявлен и потому предложен',
    );

    // Щелчок по строке применяет вид — правой панели, а не левой.
    await tester.tap(find.textContaining('Probe', findRichText: true));
    await tester.pumpAndSettle();

    expect(runtime.app.right.view, _ProbeViews.viewId);
    expect(runtime.app.left.view, PanelSettings.defaultView);
  });

  testWidgets('быстрая клавиша вида переключает активную панель', (tester) async {
    final (:runtime, tester: _) = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Cmd-9'));
    await tester.pumpAndSettle();
    expect(runtime.app.activePanel.view, _ProbeViews.viewId);

    runtime.commands.dispatch(KeyCombination.parse('Cmd-1'));
    await tester.pumpAndSettle();
    expect(runtime.app.activePanel.view, PanelSettings.defaultView);
  });

  testWidgets('смена вида не двигает курсор', (tester) async {
    final (:runtime, tester: _) = await open(tester);
    final panel = runtime.app.left;

    panel.setCursorToName('notes.txt');
    await tester.pumpAndSettle();
    final before = panel.currentEntry?.name;

    await panel.setView(_ProbeViews.viewId);
    await tester.pumpAndSettle();
    await panel.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();

    expect(panel.currentEntry?.name, before);
  });

  testWidgets('вид живёт в настройках панели', (tester) async {
    final store = InMemorySettingsStore(settings: AppSettings.defaults('/home'));
    final runtime = await testApp(
      provider: provider(),
      modules: [...featureModules(), const _ProbeViews()],
      store: store,
    );
    await runtime.app.start();

    await runtime.app.left.setView(_ProbeViews.viewId);
    await runtime.app.save();

    expect(store.saved?.left.view, _ProbeViews.viewId);
    expect(store.saved?.right.view, PanelSettings.defaultView);
  });
}

typedef AppRuntimeAndScreen = ({AppRuntime runtime, WidgetTester tester});
