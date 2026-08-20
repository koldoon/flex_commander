import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Язык подсветки по имени файла.
void main() {
  test('расширение как есть', () {
    expect(languageOf('main.dart'), 'dart');
    expect(languageOf('build.gradle'), 'gradle');
  });

  test('привычные сокращения приводятся к имени языка', () {
    expect(languageOf('pubspec.yml'), 'yaml');
    expect(languageOf('script.sh'), 'bash');
    expect(languageOf('header.h'), 'cpp');
  });

  test('файлы, у которых имя вместо расширения', () {
    expect(languageOf('Makefile'), 'makefile');
    expect(languageOf('Dockerfile'), 'dockerfile');
  });

  test('регистр не важен', () {
    expect(languageOf('MAIN.DART'), 'dart');
  });

  group('подсвечивать нечем', () {
    test('незнакомое расширение', () {
      // `.log` — тот самый случай, на котором падал разбор: языка нет, и это
      // обычное дело.
      expect(languageOf('yarn-error.log'), isNull);
    });

    test('расширения нет вовсе', () {
      expect(languageOf('LICENSE'), isNull);
    });

    test('точка в конце имени', () {
      expect(languageOf('strange.'), isNull);
    });
  });
}
