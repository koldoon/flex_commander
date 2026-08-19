import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вторая тема — чтобы было между чем переключаться.
class _NightTheme implements FcModule {
  const _NightTheme();

  @override
  String get id => 'test.night';

  @override
  String get title => 'Night';

  @override
  void install(FcRegistry registry) {
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

    expect(runtime.commands.run('app.theme.use', parameters: {SwitchThemeCommand.themeIdParam: 'night'}), isTrue);
    expect(runtime.theme.current.id, 'night');

    // Запись отложенная, как и у остальных настроек.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(serialize(store.saved!.modules), containsPair('fc.default_theme', {'themeId': 'night'}));
  });

  test('без параметра команда переключает по кругу', () async {
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme(), const _NightTheme()]);

    runtime.commands.run('app.theme.use');
    expect(runtime.theme.current.id, 'night');

    runtime.commands.run('app.theme.use');
    expect(runtime.theme.current.id, DefaultTheme.themeId);
  });

  test('с одной темой переключать нечего', () async {
    final runtime = await testApp(provider: provider, modules: [const DefaultTheme()]);

    // Команда есть, но приглушена: одна тема — это не выбор.
    final command = runtime.commands.find('app.theme.use');
    expect(command, isNotNull);
    expect(runtime.commands.isExecutable(command!), isFalse);
  });

  // Проверка «без оформления сборка не начинается» — в тестах сборки
  // приложения: она про сборку, а не про этот модуль.
}
