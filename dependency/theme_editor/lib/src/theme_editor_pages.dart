import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

import 'role_title.dart';
import 'theme_overlay.dart';
import 'theme_roles.dart';

/// Разделы окна редактора: роль — поле, группа контракта — раздел.
///
/// Разделы строятся **здесь**, а не кладутся в `SettingsCatalog`: попав туда,
/// полторы сотни ролей встали бы и в окно настроек
/// (`docs/spec/theme-editor.md`, §3).
List<SettingsPage> themeEditorPages(ThemeService themes, ThemeOverlay overlay, {required void Function() save}) {
  // Палитра — цвета, уже стоящие в теме: подбирая цвет роли, чаще всего берут
  // тот, которым покрашено соседнее. Своего списка «красивых цветов» у
  // редактора нет и быть не может — он не знает, какая тема на экране.
  final palette = <Color>{for (final role in colorRoles) role.read(themes.current.colors)}.toList();

  final pages = <String, List<SettingsField>>{};
  void put(String section, SettingsField field) => pages.putIfAbsent(section, () => []).add(field);

  for (final role in colorRoles) {
    put(
      role.section,
      SettingsField.color(
        role.name,
        title: roleTitle(role.name),
        palette: palette,
        // Умолчание — значение **базовой темы**: с ним форма сравнивает
        // нынешнее, решая, помечать ли роль тронутой.
        defaultValue: role.read(overlay.pristine.colors),
        read: () => role.read(themes.current.colors),
        // Цвет, равный темину, — это не правка, а её отсутствие: так «Reset»
        // формы (он пишет умолчание) убирает роль из накладки, а не записывает
        // её значением (`docs/spec/theme-editor.md`, §9).
        write: (value) => overlay.setColor(role.name, value == role.read(overlay.pristine.colors) ? null : value),
      ),
    );
  }

  for (final role in metricRoles) {
    put(
      role.section,
      SettingsField.decimal(
        role.name,
        title: roleTitle(role.name),
        min: role.kind.min,
        max: role.kind.max,
        defaultValue: role.read(overlay.pristine.metrics),
        read: () => role.read(themes.current.metrics),
        write: (value) => overlay.setMetric(role.name, value == role.read(overlay.pristine.metrics) ? null : value),
      ),
    );
  }

  final fonts = overlay.pristine.fonts;
  put(
    fontSection,
    SettingsField.text(
      'ui',
      title: 'Interface font',
      description: 'Family name; empty means the one the system picks',
      defaultValue: fonts.ui,
      read: () => themes.current.fonts.ui,
      write: (value) => overlay.setUiFont(value == fonts.ui ? null : value),
    ),
  );
  put(
    fontSection,
    SettingsField.text(
      'fixed',
      title: 'File list font',
      description: 'Monospaced, so that sizes and dates stand in columns',
      defaultValue: fonts.fixed,
      read: () => themes.current.fonts.fixed,
      write: (value) => overlay.setFixedFont(value == fonts.fixed ? null : value),
    ),
  );
  put(
    fontSection,
    SettingsField.list(
      'fixedFallback',
      title: 'File list fallback fonts',
      description: 'What to set the list in when the font above is not installed',
      hint: 'Menlo',
      defaultValue: fonts.fixedFallback,
      read: () => themes.current.fonts.fixedFallback,
      write: (value) => overlay.setFallback(_sameFonts(value, fonts.fixedFallback) ? null : value),
    ),
  );

  return [
    for (final entry in pages.entries)
      SettingsPage(title: entry.key, build: () => SettingsSchema(entry.value, save: save)),
  ];
}

/// Списки шрифтов равны — значит своего списка нет: запись, повторяющая тему,
/// правкой не считается.
bool _sameFonts(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var at = 0; at < a.length; at++) {
    if (a[at] != b[at]) {
      return false;
    }
  }
  return true;
}
