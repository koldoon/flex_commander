import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль с подставным заголовком: приложение о нём ничего не знает заранее —
/// ровно так же, как о будущих крошках (Г14).
class _ProbeHeader implements FcFrontendModule {
  const _ProbeHeader();

  static const String headerId = 'probe';

  /// Ширина, доставшаяся заголовку в последний раз: по ней видно, что плашка
  /// вычла слот со стрелками.
  static double lastWidth = -1;

  @override
  String get id => 'test.header';

  @override
  String get title => 'Header probe';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.panelHeader(
      PanelHeaderSpec(
        id: headerId,
        title: 'Probe',
        description: 'A header that only a test declares',
        build: (context, view) {
          lastWidth = view.width;
          return Text('проба: ${view.text}', style: view.style);
        },
      ),
    );
  }
}

/// Заголовок панели рисует модуль.
///
/// Спецификация — `docs/spec/panel-header.md`.
void main() {
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/docs'),
    FakeEntry.file('/home/notes.txt', size: 10),
  ])..home = '/home';

  Future<AppRuntime> open(WidgetTester tester, {AppSettings? settings, InMemorySettingsStore? store}) async {
    final runtime = await testApp(
      provider: provider(),
      modules: [...featureModules(), const _ProbeHeader()],
      settings: settings,
      store: store,
    );

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
    return runtime;
  }

  AppSettings withHeader(String header) => AppSettings.defaults('/home')..panelHeader = header;

  testWidgets('без выбора адрес показан строкой — как было всегда', (tester) async {
    await open(tester);

    expect(find.byType(FcPathText), findsWidgets);
    expect(find.textContaining('проба:'), findsNothing);
  });

  testWidgets('выбранный заголовок достаётся обеим панелям', (tester) async {
    await open(tester, settings: withHeader(_ProbeHeader.headerId));

    // Обеим: заголовок — настройка приложения, а не панели (§6).
    expect(find.textContaining('проба: /home'), findsNWidgets(2));
    expect(find.byType(FcPathText), findsNothing);
  });

  testWidgets('чужое имя возвращает плашку, а из настроек не стирается', (tester) async {
    // Так выглядит выключенный модуль: имя в файле осталось, объявившего нет.
    final runtime = await open(tester, settings: withHeader('crumbs-of-a-module-we-do-not-have'));

    expect(find.byType(FcPathText), findsWidgets);
    expect(runtime.app.panelHeader, 'crumbs-of-a-module-we-do-not-have');
  });

  testWidgets('смена заголовка доходит до панелей на ходу', (tester) async {
    final runtime = await open(tester);

    runtime.app.setPanelHeader(_ProbeHeader.headerId);
    await tester.pumpAndSettle();

    expect(find.textContaining('проба: /home'), findsNWidgets(2));
  });

  testWidgets('заголовку достаётся ширина без слота со стрелками', (tester) async {
    await open(tester, settings: withHeader(_ProbeHeader.headerId));

    // С шириной **панели**, а не плашки: плашка облегает содержимое и бывает
    // уже отведённого. Отведённое — это панель минус слот со стрелками: адрес
    // считается по остатку, иначе он налезет на слот (§4).
    final frame = tester.getRect(find.byType(FcPanelFrame).first);
    final arrows = tester.getRect(find.byType(HistoryArrows).first);

    expect(_ProbeHeader.lastWidth, greaterThan(0));
    expect(_ProbeHeader.lastWidth, lessThanOrEqualTo(frame.width - arrows.width));
    expect(find.byType(HistoryArrows), findsWidgets, reason: 'стрелки на месте при любом заголовке');
  });

  testWidgets('выбор переживает перезапуск', (tester) async {
    final store = InMemorySettingsStore(settings: AppSettings.defaults('/home'));
    final runtime = await open(tester, store: store);

    runtime.app.setPanelHeader(_ProbeHeader.headerId);
    await runtime.app.save();

    expect(store.saved?.panelHeader, _ProbeHeader.headerId);
  });
}
