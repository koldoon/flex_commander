import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вторая тема — чтобы было между чем переключаться.
class _NightTheme implements FcFrontendModule {
  const _NightTheme();

  @override
  String get id => 'test.night';

  @override
  String get title => 'Night';

  @override
  void installFrontend(FrontendRegistry registry) {
    // Своя палитра — наследованием: переопределяется одно, остальное берётся
    // у оформления по умолчанию.
    registry.theme(
      const FcThemeSpec(
        id: 'night',
        title: 'Night',
        colors: _NightColors(),
        metrics: DefaultMetrics(),
        icons: DefaultIcons(),
        fonts: DefaultFonts(),
      ),
    );
  }
}

/// Ночная палитра: от неё нужен один цвет, остальное — как у умолчания.
class _NightColors extends DefaultColors {
  const _NightColors();

  @override
  Color get windowBackground => const Color(0xFF000000);
}

void main() {
  late InMemoryTreeProvider provider;

  setUp(() {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home')]);
  });

  test('оформление по умолчанию — то же, что у API', () async {
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme()]);

    expect(runtime.theme.current.id, DefaultTheme.themeId);
    expect(runtime.theme.current.colors.windowBackground, const DefaultColors().windowBackground);
    expect(runtime.theme.current.metrics.rowHeight, const DefaultMetrics().rowHeight);
  });

  test('выбранная тема восстанавливается при запуске', () async {
    final settings = AppSettings.defaults('/home');
    settings.modules.fromMap({
      'fc.default_theme': {'themeId': 'night'},
    });

    final runtime = await testApp(
      provider: provider,
      modules: [const DefaultTheme(), const _NightTheme()],
      settings: settings,
    );

    expect(runtime.theme.current.id, 'night');
  });

  test('незнакомое имя темы откатывается на умолчание', () async {
    final settings = AppSettings.defaults('/home');
    settings.modules.fromMap({
      'fc.default_theme': {'themeId': 'solarized'},
    });

    // Модуль темы могли отключить между запусками — это не повод не открыться.
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme()], settings: settings);

    expect(runtime.theme.current.id, DefaultTheme.themeId);
  });

  test('команда меняет тему и запоминает выбор', () async {
    final store = InMemorySettingsStore();
    final runtime = await testApp(
      provider: provider,
      modules: [const DefaultTheme(), const _NightTheme()],
      store: store,
    );

    expect(
      runtime.commands.run(
        'app.theme.use',
        const CommandInvocation(parameters: {SwitchThemeCommand.themeIdParam: 'night'}),
      ),
      isTrue,
    );
    expect(runtime.theme.current.id, 'night');

    // Запись отложенная, как и у остальных настроек.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(serialize(store.saved!.modules), containsPair('fc.default_theme', {'themeId': 'night'}));
  });

  test('без параметра команда переключает по кругу', () async {
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme(), const _NightTheme()]);

    // Круг проверяется длиной списка, а не перечислением имён: тем у модуля
    // теперь три, и тест, знающий их наперечёт, падал бы от каждой новой.
    final order = runtime.theme.available.map((theme) => theme.id).toList();
    expect(order.first, DefaultTheme.themeId, reason: 'умолчание — первая в списке');

    for (var step = 1; step < order.length; step++) {
      runtime.commands.run('app.theme.use');
      expect(runtime.theme.current.id, order[step]);
    }

    // Столько шагов, сколько тем, — и мы там, откуда вышли.
    runtime.commands.run('app.theme.use');
    expect(runtime.theme.current.id, DefaultTheme.themeId);
  });

  test('с одной темой переключать нечего', () async {
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme()]);

    // Оформлений у модуля три; оставляем одно — проверяется утверждение «одна
    // тема это не выбор», а не то, сколько их приносит модуль.
    runtime.theme.forget(MacOsThemeIds.light);
    runtime.theme.forget(MacOsThemeIds.dark);
    expect(runtime.theme.available.length, 1);

    // Команда есть, но приглушена.
    final command = runtime.commands.find('app.theme.use');
    expect(command, isNotNull);
    expect(runtime.commands.isExecutable(command!), isFalse);
  });

  test('оформления macOS приезжают вместе с референсным, и оно остаётся первым', () async {
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme()]);

    final ids = runtime.theme.available.map((theme) => theme.id).toList();
    expect(ids, [DefaultTheme.themeId, MacOsThemeIds.light, MacOsThemeIds.dark]);

    // Порядок держит умолчание: выбора ещё не было, а тема уже есть.
    expect(runtime.theme.current.id, DefaultTheme.themeId);
  });

  test('имена оформлений macOS не занять своей темой', () {
    // `id` своей темы выводится из названия заменой всего, что не буква и не
    // цифра, на дефис, — точку такое правило не произведёт никогда. Поэтому
    // накладка редактора, выкладываемая после сборки, встроенное не вытеснит.
    for (final id in [MacOsThemeIds.light, MacOsThemeIds.dark]) {
      expect(id, contains('.'));
    }
  });

  test('у светлого оформления яркость светлая, у тёмного — тёмная', () {
    // Умолчание конструктора спеки тёмное, и забыть его у светлой темы легче
    // всего: соврали бы полосы прокрутки и курсор в полях.
    expect(macOsLightTheme().brightness, Brightness.light);
    expect(macOsDarkTheme().brightness, Brightness.dark);
  });

  test('без службы акцента оформления берут синий, с нею — её цвет', () {
    // Канала нет в тестах и на другой платформе — это законный случай, а не
    // ошибка.
    expect((macOsLightTheme().colors as MacOsColors).cursorBackground, macOsBlueAccent);

    const pink = Color(0xFFFF2D55);
    expect((macOsLightTheme(accent: pink).colors as MacOsColors).cursorBackground, pink);
  });

  // Проверка «без оформления сборка не начинается» — в тестах сборки
  // приложения: она про сборку, а не про этот модуль.
}
