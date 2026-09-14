import 'package:fc_panels/fc_panels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор адреса на звенья (`docs/spec/panel-crumbs.md`, §2).
void main() {
  List<String> labels(String address) => crumbsOf(address).map((crumb) => crumb.label).toList();
  List<String> paths(String address) => crumbsOf(address).map((crumb) => crumb.path).toList();

  test('корень и каталоги под ним', () {
    expect(labels('/Users/koldoon/dev'), ['/', 'Users', 'koldoon', 'dev']);
    expect(paths('/Users/koldoon/dev'), ['/', '/Users', '/Users/koldoon', '/Users/koldoon/dev']);
  });

  test('у корня одно звено — он сам', () {
    expect(labels('/'), ['/']);
  });

  test('первое звено — корень источника, а не корень диска', () {
    // Иначе нажатие на `ssh:` увело бы в никуда.
    expect(labels('ssh://koldoon@host/var/log'), ['ssh://koldoon@host', 'var', 'log']);
    expect(paths('ssh://koldoon@host/var/log'), [
      'ssh://koldoon@host',
      'ssh://koldoon@host/var',
      'ssh://koldoon@host/var/log',
    ]);
  });

  test('голая схема — тоже адрес, и звено у неё одно', () {
    expect(labels('ftp://host'), ['ftp://host']);
  });

  test('архив звеном не выделяется: для панели это каталог', () {
    expect(labels('/home/a.zip/docs'), ['/', 'home', 'a.zip', 'docs']);
  });

  test('хвостовой разделитель лишнего звена не даёт', () {
    expect(labels('/home/docs/'), ['/', 'home', 'docs']);
    expect(paths('/home/docs/').last, '/home/docs');
  });

  test('двойные разделители пропускаются', () {
    expect(labels('/home//docs'), ['/', 'home', 'docs']);
  });

  test('текст без разделителей звеньями не становится', () {
    // Заголовок, выставленный командой, — подпись, а не адрес: делить нечего.
    expect(crumbsOf('найдено 12'), isEmpty);
    expect(crumbsOf(''), isEmpty);
  });
}
