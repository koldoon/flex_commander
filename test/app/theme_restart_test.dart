import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Своя тема переживает перезапуск — тем же путём, что в приложении: запись,
/// файл JSON, чтение при запуске (найдено на живом 2 октября 2026).
void main() {
  test('своя тема, заведённая поверх «Follow macOS», остаётся выбранной после перезапуска', () async {
    final provider = InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home';
    final store = InMemorySettingsStore(settings: AppSettings.defaults('/home'));
    final first = await testApp(provider: provider, modules: featureModules(), store: store);
    await first.app.start();

    // Сценарий человека: стоит «Follow macOS», «New» → имя → правка цвета.
    first.app.commands.run(
      SwitchThemeCommand.commandId,
      CommandInvocation(parameters: {SwitchThemeCommand.themeIdParam: MacOsThemeIds.auto}),
    );
    final overlay = first.resolve<ThemeOverlay>();
    final id = overlay.create('Personal');
    first.app.commands.run(
      SwitchThemeCommand.commandId,
      CommandInvocation(parameters: {SwitchThemeCommand.themeIdParam: id}),
    );
    overlay.setColor('windowBackground', const Color(0xFF123456));
    expect(first.app.theme.current.id, id);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final file = jsonDecode(jsonEncode(serialize(store.saved!)));
    final restored = AppSettings.defaults('/home');
    extract(restored, file);

    final second = await testApp(provider: provider, modules: featureModules(), settings: restored);
    await second.app.start();
    expect(second.app.theme.available.map((theme) => theme.title), contains('Personal'));
    expect(second.app.theme.current.id, id, reason: 'выбрана своя тема, а не Default');
    expect(second.app.theme.current.colors.windowBackground, const Color(0xFF123456));
  });
}
