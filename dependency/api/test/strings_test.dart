import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Реестр строк: ключом служит сама английская строка.
///
/// Спецификация — `docs/spec/localization.md`.
void main() {
  late String language;

  StringsRegistry build() => StringsRegistry(languageSource: () => language);

  setUp(() => language = 'ru');

  group('перевод', () {
    test('находится по английскому тексту', () {
      final strings = build()..add('ru', {'Copy': 'Копировать'});

      expect(strings.tr('Copy'), 'Копировать');
    });

    test('незнакомая строка остаётся английской', () {
      final strings = build()..add('ru', {'Copy': 'Копировать'});

      // Пустая надпись хуже непереведённой.
      expect(strings.tr('Move'), 'Move');
    });

    test('на английском словарь не спрашивается вовсе', () {
      language = 'en';
      final strings = build()..add('ru', {'Copy': 'Копировать'});

      expect(strings.tr('Copy'), 'Copy');
    });

    test('незнакомый язык — английский', () {
      language = 'fr';
      final strings = build()..add('ru', {'Copy': 'Копировать'});

      expect(strings.language, 'en');
      expect(strings.tr('Copy'), 'Copy');
    });

    test('подстановки идут по имени', () {
      final strings = build()..add('ru', {'Copy «{name}» to {where}': 'Копировать «{name}» в {where}'});

      expect(
        strings.tr('Copy «{name}» to {where}', args: {'name': 'a.txt', 'where': '/tmp'}),
        'Копировать «a.txt» в /tmp',
      );
    });

    test('оговорка разводит одинаковые тексты', () {
      final strings = build()..add('ru', {'Open': 'Открыть', 'archive|Open': 'Распаковать'});

      expect(strings.tr('Open'), 'Открыть');
      expect(strings.tr('Open', context: 'archive'), 'Распаковать');
    });

    test('оговорка без перевода не берёт перевод без оговорки', () {
      final strings = build()..add('ru', {'Open': 'Открыть'});

      // Иначе оговорка не разводила бы, а скрывала.
      expect(strings.tr('Open', context: 'archive'), 'Open');
    });

    test('два разных перевода одного ключа — ошибка сборки', () {
      final strings = build()..add('ru', {'Open': 'Открыть'});

      // Молчаливая победа последнего означала бы, что перевод зависит от
      // порядка модулей в списке.
      expect(() => strings.add('ru', {'Open': 'Распаковать'}), throwsStateError);
      // Тот же перевод дважды — не ошибка: два модуля вправе перевести
      // «Cancel» одинаково.
      expect(() => strings.add('ru', {'Open': 'Открыть'}), returnsNormally);
    });

    test('смена языка перерисовывает', () {
      final strings = build();
      var notified = 0;
      strings.addListener(() => notified++);

      strings.refresh();

      expect(notified, 1);
    });
  });

  group('множественное число', () {
    late StringsRegistry strings;

    setUp(() {
      strings = build()..addPlurals('ru', {'{n} files': (one: '{n} файл', few: '{n} файла', many: '{n} файлов')});
    });

    String files(int count) => strings.plural(count, one: '{n} file', other: '{n} files');

    test('русские формы', () {
      expect(files(1), '1 файл');
      expect(files(2), '2 файла');
      expect(files(4), '4 файла');
      expect(files(5), '5 файлов');
      expect(files(0), '0 файлов');
      expect(files(11), '11 файлов');
      expect(files(21), '21 файл');
      expect(files(112), '112 файлов');
      expect(files(114), '114 файлов');
      expect(files(122), '122 файла');
    });

    test('английский называет обе формы на месте', () {
      language = 'en';

      expect(files(1), '1 file');
      expect(files(5), '5 files');
    });

    test('непереведённое множественное остаётся английским', () {
      expect(strings.plural(5, one: '{n} folder', other: '{n} folders'), '5 folders');
    });
  });

  group('ошибки дерева', () {
    test('показываются на языке человека', () {
      final strings = build()..add('ru', {'Not found: {path}': 'Не найдено: {path}'});

      expect(strings.describe(const FsError('/home/a.txt', FsErrorKind.notFound)), 'Не найдено: /home/a.txt');
      // Английский текст значения не трогается: он уходит в журнал.
      expect(const FsError('/home/a.txt', FsErrorKind.notFound).message, 'Not found: /home/a.txt');
    });

    test('непереведённая ошибка совпадает со своим английским текстом', () {
      final strings = build();

      for (final kind in FsErrorKind.values) {
        final error = FsError('/home/a.txt', kind);
        expect(strings.describe(error), error.message, reason: '$kind');
      }
    });
  });
}
