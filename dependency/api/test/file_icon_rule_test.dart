import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Источник иконки', () {
    test('роль темы', () {
      expect(IconSource.parse('glyph:folder'), isA<GlyphRoleSource>().having((s) => s.role, 'role', 'folder'));
    });

    test('глиф кодом', () {
      expect(IconSource.parse('glyph:f07b'), isA<GlyphCodeSource>().having((s) => s.codePoint, 'codePoint', 0xf07b));
    });

    test('картинка', () {
      expect(
        IconSource.parse('image:~/icons/dart.png'),
        isA<PictureSource>().having((s) => s.path, 'path', '~/icons/dart.png'),
      );
    });

    test('система', () {
      expect(IconSource.parse('system'), isA<SystemIconSource>());
    });

    test('запись возвращается той же, какой была', () {
      for (final text in ['glyph:folder', 'glyph:f07b', 'image:~/icons/dart.png', 'system']) {
        expect(IconSource.parse(text)!.text, text);
      }
    });

    test('неразобранное — null, а не исключение', () {
      for (final text in ['', 'folder', 'glyph:', 'image:', 'значок', 'system:']) {
        expect(IconSource.parse(text), isNull, reason: 'запись «$text»');
      }
    });

    test('роль из одних шестнадцатеричных знаков читается как код', () {
      // Цена свободы писать любой глиф числом. Роли с таким именем нет ни
      // одной, поэтому спутать не с чем — но знать об этом стоит.
      expect(IconSource.parse('glyph:face'), isA<GlyphCodeSource>());
    });
  });

  group('Правило', () {
    test('условие и источник', () {
      final rule = FileIconRule.fromJson({
        'mask': '*.app',
        'kinds': ['directory'],
        'icon': 'system',
      });

      expect(rule, isNotNull);
      expect(rule!.icon, isA<SystemIconSource>());
      expect(
        rule.when.matches(FileEntry(name: 'Safari.app', kind: EntryKind.directory, path: '/Applications/Safari.app')),
        isTrue,
      );
    });

    test('без источника правила не выходит', () {
      expect(FileIconRule.fromJson({'mask': '*.app'}), isNull);
      expect(FileIconRule.fromJson({'mask': '*.app', 'icon': 'что-нибудь'}), isNull);
      expect(FileIconRule.fromJson('строка'), isNull);
    });

    test('непонятные записи списка выбрасываются, остальные остаются', () {
      final rules = FileIconRule.listFromJson([
        {'mask': '*.dart', 'icon': 'glyph:folder'},
        {'mask': '*.py'},
        'мусор',
        {'icon': 'system'},
      ]);

      expect(rules.length, 2);
      expect(rules.first.icon, isA<GlyphRoleSource>());
      expect(rules.last.icon, isA<SystemIconSource>());
    });

    test('не список — пустой список правил', () {
      expect(FileIconRule.listFromJson(null), isEmpty);
      expect(FileIconRule.listFromJson('правила'), isEmpty);
    });

    test('туда и обратно', () {
      final json =
          FileIconRule.listFromJson([
            {'mask': '*.dart', 'icon': 'image:~/dart.png'},
          ]).first.toJson();

      expect(json, {'mask': '*.dart', 'icon': 'image:~/dart.png'});
    });
  });
}
