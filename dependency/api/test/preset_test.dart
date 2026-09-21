import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Набор выбора: хранение и разбор (`docs/spec/settings-presets.md`).
void main() {
  Preset working() => Preset(
    name: 'Работа',
    settings: {
      'fc.shell': {'themeId': 'dark', 'language': 'ru'},
      'fc.terminal': {'maxLines': 20000},
    },
    keys: [KeyOverride(command: 'file.copy', was: 'F5', now: 'Cmd-Shift-Y')],
  )..put('fc.panels', 'cursorHoldsPlace', true);

  Preset reread(Preset preset) {
    final json = jsonDecode(jsonEncode(serialize(preset))) as Map<String, dynamic>;
    return Preset()..fromMap(json);
  }

  test('набор переживает запись и чтение', () {
    final back = reread(working());

    expect(back.name, 'Работа');
    expect(back.valueOf('fc.shell', 'themeId'), 'dark');
    expect(back.valueOf('fc.terminal', 'maxLines'), 20000);
    expect(back.valueOf('fc.panels', 'cursorHoldsPlace'), isTrue);
    expect(back.keys.single.now, 'Cmd-Shift-Y');
  });

  test('о чём набор молчит, того в нём и нет', () {
    // На этом стоит применение: нет значения — поле вернётся к умолчанию.
    expect(working().valueOf('fc.editor', 'wrap'), isNull);
    expect(working().valueOf('fc.shell', 'listingCache'), isNull);
  });

  test('чужое значение пропускается молча', () {
    // Набор мог прийти из другого выпуска: падать на нём незачем.
    final back =
        Preset()..fromMap({
          'name': 'Чужой',
          'settings': {
            'fc.shell': {
              'themeId': 'dark',
              'weird': {'nested': 1},
            },
            'broken': 'не словарь',
          },
        });

    expect(back.valueOf('fc.shell', 'themeId'), 'dark');
    expect(back.valueOf('fc.shell', 'weird'), isNull);
    expect(back.settings.containsKey('broken'), isFalse);
  });

  test('безымянный набор не годится к делу', () {
    expect(Preset().isSane, isFalse);
    expect(Preset(name: 'Дом').isSane, isTrue);
  });

  test('наборы живут в настройках рядом с прочим выбором', () {
    final settings =
        AppSettings.defaults('/home')
          ..presets.add(working())
          ..preset = 'Работа';

    final saved = <String, dynamic>{};
    settings.toMap(saved);
    final back = AppSettings.defaults('/home')..fromMap(jsonDecode(jsonEncode(serialize(settings))));

    expect(saved['preset'], 'Работа', reason: 'у поля схемы обязан быть ключ в настройках');
    expect(back.preset, 'Работа');
    expect(back.presets.single.valueOf('fc.shell', 'themeId'), 'dark');
  });

  test('безымянный набор в настройки не попадает', () {
    final settings = AppSettings.defaults('/home')..presets.add(Preset());
    final back = AppSettings.defaults('/home')..fromMap(jsonDecode(jsonEncode(serialize(settings))));

    expect(back.presets, isEmpty);
  });
}
