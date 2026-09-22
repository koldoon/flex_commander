import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вторая тема: важно не то, какая она, а то, что выбирать есть из чего —
/// команда смены темы при единственной теме невыполнима.
const _light = FcThemeSpec(
  id: 'light',
  title: 'Light',
  colors: DefaultColors(),
  metrics: DefaultMetrics(),
  icons: DefaultIcons(),
  fonts: DefaultFonts(),
);

/// Редактор тем (`docs/spec/theme-editor.md`).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
  });

  SettingsField fieldOf(String module, String id) => [
    for (final page in runtime.resolve<SettingsCatalog>().pages)
      if (page.id == module) ...page.build().fields,
  ].firstWhere((field) => field.id == id);

  test('выбор темы в окне настроек доезжает до раздела настроек', () {
    runtime.app.theme.register(_light);

    (fieldOf('fc.shell', 'themeId') as SettingsChoice).write('light');

    expect(runtime.app.theme.current.id, 'light');
    // Имя сохраняет команда, а не служба: правка мимо неё переживала бы
    // перезапуск только на словах (`docs/spec/theme-editor.md`, §13).
    expect(runtime.app.settings.modules.scope(DefaultTheme.commandId).section(ThemeSettings.new).themeId, 'light');
  });
}
