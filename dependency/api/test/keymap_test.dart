import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Набор клавиш: хранение, разбор и переезд с пресетов
/// (`docs/spec/keymaps.md`).
void main() {
  AppSettings reread(Object stored) => AppSettings.defaults('/home')..fromMap(jsonDecode(jsonEncode(stored)));

  test('набор переживает запись и чтение', () {
    final keymap = Keymap(name: 'Дом', keys: [KeyOverride(binding: 'file.copy', key: 'Cmd-Shift-Y')]);
    final back = Keymap()..fromMap(jsonDecode(jsonEncode(serialize(keymap))) as Map<String, dynamic>);

    expect(back.name, 'Дом');
    expect(back.keys.single.key, 'Cmd-Shift-Y');
  });

  test('читается и прежний файл пресета', () {
    final back =
        Keymap()..fromMap({
          'name': 'Старый',
          'settings': {
            'fc.shell': {'themeId': 'dark'},
          },
          'keys': [
            {'binding': 'file.copy', 'key': 'Ctrl-Y'},
          ],
        });

    expect(back.name, 'Старый');
    expect(back.keys.single.binding, 'file.copy');
  });

  test('выбор, свои наборы и правки живут в настройках', () {
    final settings =
        AppSettings.defaults('/home')
          ..keymap = 'mc'
          ..keymaps.add(Keymap(name: 'Дом', keys: [KeyOverride(binding: 'file.copy', key: 'Ctrl-Y')]))
          ..keymapEdits['mc'] = [KeyOverride(binding: 'file.remove', key: 'Ctrl-D')];

    final back = reread(serialize(settings));

    expect(back.keymap, 'mc');
    expect(back.keymaps.single.name, 'Дом');
    expect(back.keymaps.single.keys.single.key, 'Ctrl-Y');
    expect(back.keymapEdits['mc']!.single.key, 'Ctrl-D');
  });

  test('записи разбираются из любого словаря', () {
    // Через границу изолятов вложенные словари приезжают `<dynamic, dynamic>`
    // (память: «списки в разделе модуля»).
    final back = AppSettings.defaults('/home')..fromMap(<String, dynamic>{
      'keymap': 'Дом',
      'keymaps': [
        <dynamic, dynamic>{
          'name': 'Дом',
          'keys': [
            <dynamic, dynamic>{'binding': 'file.copy', 'key': 'Ctrl-Y'},
          ],
        },
      ],
      'keymapEdits': <dynamic, dynamic>{
        'mc': [
          <dynamic, dynamic>{'binding': 'file.remove', 'key': 'Ctrl-D'},
        ],
      },
    });

    expect(back.keymaps.single.keys.single.key, 'Ctrl-Y');
    expect(back.keymapEdits['mc']!.single.key, 'Ctrl-D');
  });

  test('переезд: свои пресеты с клавишами становятся наборами, выбор сохраняется', () {
    final back = reread({
      'preset': 'Работа',
      'presets': [
        {
          'name': 'Работа',
          'settings': {
            'fc.shell': {'themeId': 'dark'},
          },
          'keys': [
            {'binding': 'file.copy', 'key': 'Ctrl-Y'},
          ],
        },
        {
          'name': 'Только тема',
          'settings': {
            'fc.shell': {'themeId': 'dark'},
          },
        },
      ],
    });

    expect(back.keymap, 'Работа');
    expect(back.keymaps.map((item) => item.name), ['Работа'], reason: 'пресет без клавиш набором клавиш не стал');
    expect(back.keymaps.single.keys.single.key, 'Ctrl-Y');
    expect(back.presets, isEmpty, reason: 'пресеты читать больше некому');
    expect(serialize(back), isNot(contains('presets')));
  });

  test('переезд: выбранный встроенный остаётся выбранным', () {
    final back = reread({'preset': 'mc'});

    expect(back.keymap, 'mc');
    expect(back.keymaps, isEmpty);
  });

  test('переезд один раз: записанные наборы пресетами не перетираются', () {
    final back = reread({
      'keymap': '',
      'preset': 'mc',
      'presets': [
        {
          'name': 'Работа',
          'keys': [
            {'binding': 'file.copy', 'key': 'Ctrl-Y'},
          ],
        },
      ],
    });

    expect(back.keymap, isEmpty);
    expect(back.keymaps, isEmpty);
  });

  test('безымянный набор в настройки не попадает', () {
    final back = reread({
      'keymaps': [
        {'name': '', 'keys': []},
      ],
    });

    expect(back.keymaps, isEmpty);
  });
}
