import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Быстрый поиск в панели: курсор идёт за набранным.
void main() {
  late AppRuntime runtime;

  Panel panel() => runtime.app.left;
  String? cursor() => panel().currentNode?.name;

  bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

  /// Набрать — как с клавиатуры: каждая буква отдельным нажатием.
  void type(String text) {
    for (final character in text.split('')) {
      runtime.commands.dispatch(KeyCombination.parse(character));
    }
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.directory('/home/downloads'),
        FakeEntry.file('/home/notes.txt', size: 10),
        FakeEntry.file('/home/dog.png', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Ctrl-S включает режим, но курсор не двигает', () {
    expect(panel().quickSearch, isNull);

    expect(press('Ctrl-S'), isTrue);

    expect(panel().quickSearch, '', reason: 'включён, но ничего не набрано');
    expect(cursor(), '..', reason: 'искать ещё нечего');
  });

  test('курсор идёт за набранным, с начала имени', () {
    press('Ctrl-S');
    type('do');

    expect(panel().quickSearch, 'do');
    expect(cursor(), 'docs');

    type('w');
    expect(panel().quickSearch, 'dow');
    expect(cursor(), 'downloads');
  });

  test('буква, которая никуда не ведёт, не принимается', () {
    // Иначе после первой же опечатки не находится ничего, и стирать
    // приходится вслепую.
    press('Ctrl-S');
    type('do');
    type('z');

    expect(panel().quickSearch, 'do', reason: 'образец не вырос');
    expect(cursor(), 'docs', reason: 'и курсор остался');
  });

  test('повторный Ctrl-S идёт к следующему такому же и по кругу', () {
    press('Ctrl-S');
    type('d');
    expect(cursor(), 'docs');

    press('Ctrl-S');
    expect(cursor(), 'downloads');

    press('Ctrl-S');
    expect(cursor(), 'dog.png');

    press('Ctrl-S');
    expect(cursor(), 'docs', reason: 'по кругу');
  });

  test('Backspace укорачивает образец, режим остаётся', () {
    press('Ctrl-S');
    type('dow');
    expect(cursor(), 'downloads');

    expect(press('Backspace'), isTrue);
    expect(panel().quickSearch, 'do');
    expect(panel().quickSearch, isNotNull, reason: 'стирают, чтобы набрать иначе, а не чтобы выйти');
  });

  test('Esc выходит, курсор остаётся где стоял', () {
    press('Ctrl-S');
    type('dow');
    expect(cursor(), 'downloads');

    expect(press('Esc'), isTrue);

    expect(panel().quickSearch, isNull);
    expect(cursor(), 'downloads');
  });

  test('«..» не совпадает даже на точку', () {
    press('Ctrl-S');
    type('.');

    expect(panel().quickSearch, '', reason: 'точка никуда не ведёт: «..» — не имя файла');
    expect(cursor(), '..');
  });

  test('уход в другой каталог выключает режим', () async {
    press('Ctrl-S');
    type('do');
    expect(panel().quickSearch, 'do');

    await panel().openPath('/home/docs');

    expect(panel().quickSearch, isNull, reason: 'образец относится к прежнему списку');
  });

  test('без режима буква по-прежнему прыгает по первой букве', () {
    // Печать сама по себе работает как раньше: `GoToNameCommand` никуда не
    // делась, и быстрый поиск её не заменяет.
    type('n');

    expect(panel().quickSearch, isNull);
    expect(cursor(), 'notes.txt');
  });
}
