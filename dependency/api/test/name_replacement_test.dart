import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Замена в имени и регистр (`docs/spec/multi-rename.md`, §6 и §7).
void main() {
  group('замена', () {
    test('буквальная меняет все вхождения', () {
      final replacement = NameReplacement.parse('_', '-');

      expect(replacement.apply('IMG_2026_03.JPG'), 'IMG-2026-03.JPG');
    });

    test('регистр по умолчанию не важен', () {
      expect(NameReplacement.parse('img', 'Фото').apply('IMG_0041.JPG'), 'Фото_0041.JPG');
      expect(
        NameReplacement.parse('img', 'Фото', caseSensitive: true).apply('IMG_0041.JPG'),
        'IMG_0041.JPG',
        reason: 'просили различать — различаем',
      );
    });

    test('буквальная замена группой ничего не считает', () {
      // Про выражения человек не просил, и превращать его текст в подстановку
      // значило бы удивлять на ровном месте.
      expect(NameReplacement.parse('_', r'$1').apply('a_b'), r'a$1b');
    });

    test('выражением подставляются группы', () {
      final replacement = NameReplacement.parse(r'IMG_(\d+)', r'Отпуск-$1', regexp: true);

      expect(replacement.apply('IMG_0041.JPG'), 'Отпуск-0041.JPG');
    });

    test('доллар пишется удвоением', () {
      expect(NameReplacement.parse('a', r'$$', regexp: true).apply('a'), r'$');
    });

    test('неверное выражение не бросает, а гасит годность', () {
      final replacement = NameReplacement.parse('(', 'x', regexp: true);

      expect(replacement.isValid, isFalse);
      expect(replacement.apply('(abc)'), '(abc)', reason: 'негодная замена ничего не трогает');
    });

    test('пустое «найти» — правила нет', () {
      final replacement = NameReplacement.parse('', 'x');

      expect(replacement.isEmpty, isTrue);
      expect(replacement.isValid, isTrue);
      expect(replacement.apply('имя'), 'имя');
    });
  });

  group('регистр', () {
    test('верхний и нижний', () {
      expect(RenameCase.upper.apply('Отчёт за год'), 'ОТЧЁТ ЗА ГОД');
      expect(RenameCase.lower.apply('ОТЧЁТ.PDF'), 'отчёт.pdf');
    });

    test('первая заглавная', () {
      expect(RenameCase.sentence.apply('отчёт ЗА год'), 'Отчёт за год');
    });

    test('каждое слово — по пробелам, чёрточкам и точкам', () {
      expect(RenameCase.words.apply('отчёт за_год-2026.часть'), 'Отчёт За_Год-2026.Часть');
    });

    test('без изменений ничего не трогает', () {
      expect(RenameCase.keep.apply('КаК БыЛо'), 'КаК БыЛо');
    });
  });
}
