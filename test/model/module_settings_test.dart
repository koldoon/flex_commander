import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Настройки модуля: раздел под своим именем.
class _ThemeSettings implements Serializable {
  _ThemeSettings({this.themeId = 'default'});

  String themeId;

  @override
  void fromMap(Map<String, dynamic> m) => themeId = extract(themeId, m['themeId']);

  @override
  void toMap(Map<String, dynamic> m) => m['themeId'] = themeId;
}

void main() {
  group('раздел модуля', () {
    test('умолчания берутся из самого модуля', () {
      final settings = ModuleSettings();

      expect(settings.scope('fc.theme').section(_ThemeSettings.new).themeId, 'default');
    });

    test('прочитанное из файла дописывается в умолчания', () {
      final settings =
          ModuleSettings()..fromMap({
            'fc.theme': {'themeId': 'light'},
          });

      expect(settings.scope('fc.theme').section(_ThemeSettings.new).themeId, 'light');
    });

    test('раздел, который вовсе не объект, пропускается', () {
      final settings =
          ModuleSettings()..fromMap({
            'fc.theme': {'themeId': 'light'},
            'fc.broken': 'вообще не раздел',
          });

      // Испорченный раздел не должен мешать остальным — ни при чтении, ни при
      // записи: его просто нет.
      expect(settings.scope('fc.theme').section(_ThemeSettings.new).themeId, 'light');
      expect(settings.namespaces, isNot(contains('fc.broken')));
    });

    test('отсутствующее значение остаётся умолчанием', () {
      final settings =
          ModuleSettings()..fromMap({
            'fc.theme': {'somethingElse': true},
          });

      // Конверторы пакета терпимы: число стало бы строкой, — а вот пустоте
      // взяться неоткуда, и остаётся то, что задал сам модуль.
      expect(settings.scope('fc.theme').section(_ThemeSettings.new).themeId, 'default');
    });

    test('раздел один и тот же при повторном обращении', () {
      final settings = ModuleSettings();
      final first = settings.scope('fc.theme').section(_ThemeSettings.new);

      first.themeId = 'light';

      expect(settings.scope('fc.theme').section(_ThemeSettings.new).themeId, 'light');
    });

    test('просьба сохранить доходит до приложения', () {
      var saves = 0;
      final settings = ModuleSettings()..onSave = () => saves++;

      settings.scope('fc.theme').save();

      expect(saves, 1);
    });
  });

  group('запись', () {
    test('разобранный раздел пишется со свежими значениями', () {
      final settings = ModuleSettings();
      settings.scope('fc.theme').section(_ThemeSettings.new).themeId = 'light';

      expect(serialize(settings), {
        'fc.theme': {'themeId': 'light'},
      });
    });

    test('чужой раздел переживает запись нетронутым', () {
      final settings =
          ModuleSettings()..fromMap({
            'fc.theme': {'themeId': 'light'},
            'fc.ssh': {'host': 'example.org', 'port': 22},
          });

      // Модуль ssh сегодня отключён, и его раздел никто не разбирал: потерять
      // его — значит потерять настройки пользователя.
      settings.scope('fc.theme').section(_ThemeSettings.new);

      expect(serialize(settings), {
        'fc.theme': {'themeId': 'light'},
        'fc.ssh': {'host': 'example.org', 'port': 22},
      });
    });
  });

  group('в настройках приложения', () {
    test('разделы модулей переживают цикл записи и чтения', () {
      final settings = AppSettings.defaults('/home');
      settings.modules.scope('fc.theme').section(_ThemeSettings.new).themeId = 'light';
      settings.modules.fromMap({
        'fc.ssh': {'host': 'example.org'},
      });

      final restored = AppSettings.defaults('/home')
        ..fromMap(jsonDecode(jsonEncode(serialize(settings))) as Map<String, dynamic>);

      expect(restored.modules.scope('fc.theme').section(_ThemeSettings.new).themeId, 'light');
      expect(serialize(restored.modules), containsPair('fc.ssh', {'host': 'example.org'}));
    });

    test('файл без раздела модулей читается по-прежнему', () {
      final settings = AppSettings.defaults('/home')..fromMap({'splitRatio': 0.4});

      expect(settings.splitRatio, 0.4);
      expect(settings.modules.namespaces, isEmpty);
    });
  });
}
