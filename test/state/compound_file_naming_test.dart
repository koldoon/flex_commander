import 'package:flex_commander/state/compound_file_naming.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор имени со словарём составных расширений.
///
/// Словарь — правило **показа**: `archive.tar.gz` это архив `tar.gz`, а не
/// `archive.tar` с расширением `gz`. Не совпало со словарём — работает прежнее
/// правило референса.
void main() {
  CompoundFileNaming naming({List<String> compound = const [], bool useBuiltin = true}) =>
      CompoundFileNaming(compound: () => compound, useBuiltin: () => useBuiltin);

  test('встроенное составное расширение отделяется целиком', () {
    expect(naming().split('archive.tar.gz'), (base: 'archive', extension: 'tar.gz'));
    expect(naming().split('button.spec.ts'), (base: 'button', extension: 'spec.ts'));
    expect(naming().split('jquery.min.js'), (base: 'jquery', extension: 'min.js'));
  });

  test('совпадение только по границе точки', () {
    // `mytar.gz` — не `tar.gz`: у него расширение `gz`, а `my` из имени
    // выдёргивать нечего.
    expect(naming().split('mytar.gz'), (base: 'mytar', extension: 'gz'));
  });

  test('две точки сами по себе составного расширения не делают', () {
    // Иначе версия в имени превратилась бы в расширение — ровно поэтому
    // словарь, а не догадка по числу точек.
    expect(naming().split('readme.v2.txt'), (base: 'readme.v2', extension: 'txt'));
    expect(naming().split('jquery.3.7.1.js'), (base: 'jquery.3.7.1', extension: 'js'));
  });

  test('перед составным расширением должно остаться имя', () {
    // Словарь отказывается: перед `tar.gz` не осталось имени. Дальше работает
    // прежнее правило, и получается скрытый `.tar` с расширением `gz` — ровно
    // то же, что видно у `.foo.txt`.
    expect(naming().split('.tar.gz'), (base: '.tar', extension: 'gz'));
  });

  test('не совпало со словарём — прежнее правило', () {
    expect(naming().split('report.xlsx'), (base: 'report', extension: 'xlsx'));
    expect(naming().split('.gitignore'), (base: '.gitignore', extension: ''));
    expect(naming().split('file.superlongending'), (base: 'file.superlongending', extension: ''));
  });

  test('регистр остаётся человеческим', () {
    // В словаре `tar.gz`, а в колонке — то, что написано в имени.
    expect(naming().split('Archive.TAR.GZ'), (base: 'Archive', extension: 'TAR.GZ'));
  });

  test('пользовательское расширение добавляется к встроенным', () {
    final n = naming(compound: ['cfg.json']);
    expect(n.split('server.cfg.json'), (base: 'server', extension: 'cfg.json'));
    expect(n.split('archive.tar.gz'), (base: 'archive', extension: 'tar.gz'));
  });

  test('пользовательское побеждает встроенное', () {
    // Своё стоит над общим: `min.js` из словаря пользователя длиннее, и
    // спрашивается он первым.
    final n = naming(compound: ['bundle.min.js']);
    expect(n.split('app.bundle.min.js'), (base: 'app', extension: 'bundle.min.js'));
  });

  test('встроенный список можно выключить целиком', () {
    final n = naming(compound: ['cfg.json'], useBuiltin: false);
    expect(n.split('archive.tar.gz'), (base: 'archive.tar', extension: 'gz'));
    expect(n.split('server.cfg.json'), (base: 'server', extension: 'cfg.json'));
  });

  test('пустая запись в словаре ничего не ломает', () {
    // Список правится строкой в окне настроек — лишние разделители неизбежны.
    final n = naming(compound: ['', '  '], useBuiltin: false);
    expect(n.split('report.xlsx'), (base: 'report', extension: 'xlsx'));
  });
}
