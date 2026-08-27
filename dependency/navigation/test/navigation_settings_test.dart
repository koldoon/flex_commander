import 'package:fc_navigation/fc_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('история адресов', () {
    test('свежее впереди', () {
      final settings = NavigationSettings();

      settings.remember('/etc');
      settings.remember('/home');

      expect(settings.recentPaths, ['/home', '/etc']);
    });

    test('повтор поднимается наверх, а не удваивается', () {
      final settings =
          NavigationSettings()
            ..remember('/etc')
            ..remember('/home')
            ..remember('/etc');

      // Иначе список коротких походов по одним и тем же местам вытеснил бы
      // сам себя.
      expect(settings.recentPaths, ['/etc', '/home']);
    });

    test('пустой адрес не запоминается', () {
      final settings =
          NavigationSettings()
            ..remember('   ')
            ..remember('');

      expect(settings.recentPaths, isEmpty);
    });

    test('предел вытесняет самый старый', () {
      final settings =
          NavigationSettings(recentPathsLimit: 2)
            ..remember('/a')
            ..remember('/b')
            ..remember('/c');

      expect(settings.recentPaths, ['/c', '/b']);
    });

    test('уменьшенный предел действует сразу на показ', () {
      final settings =
          NavigationSettings()
            ..remember('/a')
            ..remember('/b')
            ..remember('/c');

      settings.recentPathsLimit = 2;

      // Показ короче немедленно…
      expect(settings.shownPaths, ['/c', '/b']);
      // …а список подрезается при следующей записи: лишней записи в файл на
      // каждое движение настройки не случается.
      expect(settings.recentPaths, hasLength(3));

      settings.remember('/d');
      expect(settings.recentPaths, ['/d', '/c']);
    });

    test('нулевой предел показывает пустой список', () {
      final settings = NavigationSettings(recentPathsLimit: 0)..remember('/a');

      expect(settings.shownPaths, isEmpty);
    });

    test('история переживает перезапуск', () {
      final saved = <String, dynamic>{};
      (NavigationSettings()
            ..remember('/etc')
            ..recentPathsLimit = 7)
          .toMap(saved);

      final restored = NavigationSettings()..fromMap(saved);

      expect(restored.recentPaths, ['/etc']);
      expect(restored.recentPathsLimit, 7);
    });
  });

  group('пароль в историю не попадает', () {
    test('из адреса он убирается, а имя остаётся', () {
      // Файл настроек лежит открытым текстом.
      expect(addressWithoutPassword('ssh://user:secret@host/srv'), 'ssh://user@host/srv');
    });

    test('адрес без пароля не меняется', () {
      expect(addressWithoutPassword('ssh://user@host/srv'), 'ssh://user@host/srv');
      expect(addressWithoutPassword('ssh://host/srv'), 'ssh://host/srv');
    });

    test('обычный путь возвращается как есть', () {
      // Разбирать в нём нечего — а `Uri` увидел бы в собаке что-то своё.
      expect(addressWithoutPassword('/etc'), '/etc');
      expect(addressWithoutPassword('~/Downloads'), '~/Downloads');
      expect(addressWithoutPassword('/home/mail@old'), '/home/mail@old');
    });
  });
}
