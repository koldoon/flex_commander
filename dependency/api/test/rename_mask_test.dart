import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Маска переименования (`docs/spec/multi-rename.md`, §3).
void main() {
  const photo = RenameSubject(
    base: 'IMG_0041',
    extension: 'JPG',
    parentName: 'Отпуск',
    grandParentName: 'Фото',
    date: null,
  );

  String expand(String mask, [RenameSubject subject = photo]) => RenameMask.parse(mask).expand(subject);

  group('основа и расширение', () {
    test('целиком', () {
      expect(expand('[N].[E]'), 'IMG_0041.JPG');
    });

    test('один знак', () {
      expect(expand('[N5]'), '0');
    });

    test('срез со второго по пятый', () {
      expect(expand('[N2-5]'), 'MG_0');
    });

    test('четыре знака со второго', () {
      expect(expand('[N2,4]'), 'MG_0');
    });

    test('с третьего до конца', () {
      expect(expand('[N3-]'), 'G_0041');
    });

    test('счёт с конца', () {
      expect(expand('[N-3]'), '0', reason: 'третий с конца');
      expect(expand('[N-4-]'), '0041', reason: 'с четвёртого с конца до конца');
      expect(expand('[N2--2]'), 'MG_004', reason: 'со второго по второй с конца');
    });

    test('срез за краем строки — пустота, а не ошибка', () {
      // `[N1-8]` на коротком имени обычное дело, и ругаться на него значило бы
      // запретить одну маску на разнородный список.
      expect(expand('[N1-40]'), 'IMG_0041');
      expect(expand('[N40]'), '');
      expect(expand('[E1-2]'), 'JP');
    });

    test('буквы вокруг подстановок остаются как есть', () {
      expect(expand('Отпуск_[N5-].[E]'), 'Отпуск_0041.JPG');
    });
  });

  group('счётчик', () {
    const counted = RenameSubject(base: 'a', extension: 'txt', index: 2, counter: RenameCounter(digits: 3));

    test('по полям окна', () {
      expect(expand('[C]', counted), '003', reason: 'третья строка списка');
    });

    test('свои доводы в маске старше полей', () {
      expect(expand('[C10+5:2]', counted), '20');
      expect(expand('[C:1]', counted), '3');
      expect(expand('[C100]', counted), '102');
    });

    test('номер считается по месту строки, а не по порядку вызовов', () {
      final mask = RenameMask.parse('[C]');
      const first = RenameSubject(base: 'a', extension: '', index: 0);
      const third = RenameSubject(base: 'c', extension: '', index: 2);

      expect(mask.expand(third), '3');
      expect(mask.expand(first), '1', reason: 'маска не помнит, кого разворачивала прошлый раз');
    });
  });

  group('дата и каталоги', () {
    final dated = RenameSubject(
      base: 'снимок',
      extension: 'jpg',
      parentName: 'Отпуск',
      grandParentName: 'Фото',
      date: DateTime(2026, 3, 7, 9, 5, 4),
    );

    test('части даты пишутся с нулями', () {
      expect(expand('[Y]-[M]-[D] [h][m][s]', dated), '2026-03-07 090504');
    });

    test('без даты подстановки пусты', () {
      expect(expand('[Y][M][D]'), '', reason: 'дата неизвестна — врать нечем');
    });

    test('каталог и дед', () {
      expect(expand('[P]_[G]', dated), 'Отпуск_Фото');
    });
  });

  group('негодная маска', () {
    test('незакрытая скобка — ошибка, а не текст', () {
      // Иначе сорок файлов молча стали бы «[N2-5».
      final mask = RenameMask.parse('[N2-5');

      expect(mask.isValid, isFalse);
      expect(mask.problem, isNotNull);
      expect(mask.expand(photo), '');
    });

    test('неизвестная запись названа по имени', () {
      final mask = RenameMask.parse('[Z]');

      expect(mask.isValid, isFalse);
      expect(mask.problem, contains('[Z]'));
    });

    test('разбор не бросает — его зовут на каждую букву', () {
      expect(() => RenameMask.parse('[N2-'), returnsNormally);
      expect(() => RenameMask.parse('['), returnsNormally);
      expect(() => RenameMask.parse('[]'), returnsNormally);
      expect(() => RenameMask.parse('[C1+2+3]'), returnsNormally);
    });

    test('пустая маска годна и даёт пустоту', () {
      final mask = RenameMask.parse('');

      expect(mask.isValid, isTrue);
      expect(mask.expand(photo), '');
    });
  });

  group('прочее', () {
    test('двойная скобка — сама скобка', () {
      expect(expand('[[[N]]'), '[IMG_0041]');
    });

    test('поля модулей разбираются, но пока пусты', () {
      final mask = RenameMask.parse('[=exif.taken]_[N]');

      expect(mask.isValid, isTrue);
      expect(mask.fields, {'exif.taken'});
      expect(mask.expand(photo), '_IMG_0041', reason: 'подставить пока нечем');
    });
  });
}
