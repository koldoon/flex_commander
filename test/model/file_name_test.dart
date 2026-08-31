import 'package:fc_api/fc_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор имени файла: у узла его больше нет, и правил стало два.
///
/// Расширения у файла нет — есть имя, а расширение это толкование. «Что это»
/// спрашивают чистой функцией, «как показать» — правилом показа, и различаются
/// они не придиркой, а тем, кому что нужно.
void main() {
  group('что это: последнее расширение', () {
    test('после последней точки', () {
      expect(extensionOf('report.xlsx'), 'xlsx');
      expect(extensionOf('archive.tar.gz'), 'gz');
    });

    test('точка в начале — не расширение', () {
      // `.gitignore` — имя целиком, а не файл `gitignore` неизвестного рода.
      expect(extensionOf('.gitignore'), '');
    });

    test('точки нет — расширения нет', () {
      expect(extensionOf('Makefile'), '');
    });

    test('длину не ограничивает и пробелов не боится', () {
      // Здесь спрашивают «что это»: просмотрщик сверится со своим списком, и
      // длинный хвост просто не совпадёт.
      expect(extensionOf('file.superlongending'), 'superlongending');
      expect(extensionOf('Some file.doc backup'), 'doc backup');
    });
  });

  group('как показать: правило референса', () {
    const naming = ReferenceFileNaming();

    test('обычное имя делится на имя и расширение', () {
      expect(naming.split('report.xlsx'), (base: 'report', extension: 'xlsx'));
    });

    test('берётся последнее расширение', () {
      expect(naming.split('archive.tar.gz'), (base: 'archive.tar', extension: 'gz'));
    });

    test('точка в начале — не расширение', () {
      expect(naming.split('.gitignore'), (base: '.gitignore', extension: ''));
    });

    test('слишком длинный хвост не считается расширением', () {
      // В колонке это выглядело бы враньём: `superlongending` — не расширение,
      // а часть имени.
      expect(naming.split('file.superlongending'), (base: 'file.superlongending', extension: ''));
    });

    test('хвост с пробелом не считается расширением', () {
      expect(naming.split('Some file.doc backup'), (base: 'Some file.doc backup', extension: ''));
    });
  });
}
