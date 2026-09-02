import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Имя, набранное человеком, срезается по краям — и по краям основы.
///
/// Хвостовой пробел перед точкой не виден ни в поле, ни в списке, а файл
/// получается другой.
void main() {
  test('края всего имени', () {
    expect(trimmedFileName('  отчёт.txt  '), 'отчёт.txt');
  });

  test('края основы', () {
    expect(trimmedFileName('отчёт .txt'), 'отчёт.txt');
    expect(trimmedFileName('  отчёт  .txt  '), 'отчёт.txt');
  });

  test('расширение считается тем же правилом, что рисует колонку', () {
    // У точки в начале расширения нет вовсе: это скрытый файл.
    expect(trimmedFileName('  .gitignore '), '.gitignore');
    // Составное расширение — это `gz`, значит основа `архив.tar`.
    expect(trimmedFileName('архив.tar .gz'), 'архив.tar.gz');
    // Слишком длинный хвост расширением не считается — и остаётся как есть.
    expect(trimmedFileName(' файл.оченьдлинноерасширение '), 'файл.оченьдлинноерасширение');
  });

  test('имени без расширения хватает краёв', () {
    expect(trimmedFileName('  Makefile  '), 'Makefile');
  });

  test('имя из одних пробелов остаётся пустым — и будет отвергнуто', () {
    expect(trimmedFileName('   '), isEmpty);
    // Основа из пробелов не должна превратить имя в одно расширение.
    expect(trimmedFileName('   .txt'), '.txt');
  });
}
