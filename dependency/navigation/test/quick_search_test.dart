import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Быстрый поиск в панели: курсор идёт за набранным.
void main() {
  late AppRuntime runtime;

  Panel panel() => runtime.app.left;

  /// Идущий поиск — он же признак того, что режим включён: отдельного флага
  /// нет, есть само содержимое статусной области.
  QuickSearchState? search() => QuickSearchCommand.searchIn(runtime.app);
  String? pattern() => search()?.pattern;
  String? matched() => search()?.matched;
  String? tail() => search()?.tail;
  String? cursor() => panel().currentEntry?.name;

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
    expect(search(), isNull);

    expect(press('Ctrl-S'), isTrue);

    expect(pattern(), '', reason: 'включён, но ничего не набрано');
    expect(cursor(), '..', reason: 'искать ещё нечего');
  });

  test('курсор идёт за набранным, с начала имени', () {
    press('Ctrl-S');
    type('do');

    expect(pattern(), 'do');
    expect(cursor(), 'docs');

    type('w');
    expect(pattern(), 'dow');
    expect(cursor(), 'downloads');
  });

  test('буква, которая никуда не ведёт, принимается — но хвостом', () {
    // Печатать не мешаем ничему: молчание в ответ на нажатие — худший из
    // ответов, особенно когда виновата раскладка. Ненайденное показывается
    // выделенным, курсор остаётся там, где стоял.
    press('Ctrl-S');
    type('do');
    type('z');

    expect(pattern(), 'doz', reason: 'набранное видно целиком');
    expect(matched(), 'do', reason: 'нашлось столько');
    expect(tail(), 'z', reason: 'а это ушло в хвост');
    expect(cursor(), 'docs', reason: 'курсор остался на найденном');
  });

  test('хвост не ищется дальше и стирается разом', () {
    press('Ctrl-S');
    type('do');
    // Набрано вслепую целое слово — например, не в той раскладке.
    type('zzz');

    expect(pattern(), 'dozzz');
    expect(tail(), 'zzz');
    expect(cursor(), 'docs', reason: 'курсор всё это время не двигался');

    // Один `Bsp` возвращает к последней букве, на которой что-то находилось.
    expect(press('Bsp'), isTrue);

    expect(pattern(), 'do');
    expect(tail(), '');
    expect(cursor(), 'docs');

    // Дальше стирание идёт по букве, как и раньше.
    expect(press('Bsp'), isTrue);
    expect(pattern(), 'd');
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

  test('Bsp укорачивает образец, а курсор не прыгает назад', () {
    press('Ctrl-S');
    type('dow');
    expect(cursor(), 'downloads');

    expect(press('Bsp'), isTrue);

    expect(pattern(), 'do');
    // Укороченному образцу это имя всё ещё подходит — уводить с него незачем:
    // стирают, чтобы дописать иначе, и прыжок назад тут только мешал бы.
    expect(cursor(), 'downloads');
  });

  test('стёрли всё — режим остаётся, наверх не уходим', () async {
    // Стирают, чтобы набрать иначе, а не чтобы выйти. И уж точно не затем,
    // чтобы уехать в родительский каталог: `Bsp` принадлежит набору, пока он
    // идёт, и уходит из него только `Esc`.
    press('Ctrl-S');
    type('do');

    expect(press('Bsp'), isTrue);
    expect(press('Bsp'), isTrue);
    expect(pattern(), '');

    // Стирать больше нечего — и вот тут `Bsp` раньше доставался переходу
    // наверх. Клавишу набор не отпускает: она принадлежит ему, пока он идёт.
    expect(press('Bsp'), isTrue);
    // Переход наверх — работа асинхронная, и без ожидания каталог не успел бы
    // смениться даже тогда, когда команда всё-таки выполнилась.
    await pumpEventQueue();

    expect(pattern(), '');
    expect(search(), isNotNull, reason: 'режим не выключился');
    expect(panel().directory?.pathString, '/home', reason: 'наверх не ушли');
  });

  test('без режима Bsp по-прежнему уводит наверх', () async {
    await panel().openPath('/home/docs');
    expect(panel().directory?.pathString, '/home/docs');

    expect(press('Bsp'), isTrue);
    await pumpEventQueue();

    expect(panel().directory?.pathString, '/home');
  });

  test('Esc выходит, курсор остаётся где стоял', () {
    press('Ctrl-S');
    type('dow');
    expect(cursor(), 'downloads');

    expect(press('Esc'), isTrue);

    expect(search(), isNull);
    expect(cursor(), 'downloads');
  });

  test('«..» не совпадает даже на точку', () {
    press('Ctrl-S');
    type('.');

    // Точка набирается, как и любой другой знак, но никуда не ведёт: «..» —
    // не имя файла, и совпадением оно не считается ни здесь, ни при пометке.
    expect(matched(), '', reason: 'ничего не нашлось');
    expect(tail(), '.', reason: 'и точка ушла в хвост');
    expect(cursor(), '..');
  });

  group('чужая команда закрывает полосу', () {
    // Так ведёт себя `mc`: набирают имя — полоса на экране, нажали что угодно
    // другое — её нет. Правило простое и потому предсказуемое: полоса живёт,
    // пока идут её собственные команды.
    test('стрелка закрывает — и курсор при этом двигается', () {
      press('Ctrl-S');
      type('do');
      expect(cursor(), 'docs');

      expect(press('Down'), isTrue);

      expect(search(), isNull, reason: 'полосы больше нет');
      expect(cursor(), 'downloads', reason: 'а стрелка сделала своё дело');
    });

    test('Tab закрывает', () {
      press('Ctrl-S');
      type('d');

      press('Tab');

      expect(search(), isNull);
    });

    test('команда, запущенная не с клавиатуры, — тоже', () {
      // Из палитры, кнопкой, из меню: путь один и тот же, и правило одно.
      press('Ctrl-S');
      type('d');

      expect(runtime.commands.run('panel.selection.all'), isTrue);

      expect(search(), isNull);
    });

    test('свои команды полосу оставляют', () {
      press('Ctrl-S');
      expect(search(), isNotNull);

      // Буква, повтор поиска и стирание — всё это сам поиск.
      type('d');
      expect(search(), isNotNull);
      press('Ctrl-S');
      expect(search(), isNotNull);
      press('Bsp');
      expect(search(), isNotNull);
      expect(pattern(), '');
    });

    test('невыполнимая команда полосы не трогает', () {
      // Клавиша, под которой ничего не выполнилось, — это не «другая команда»,
      // а несостоявшееся нажатие: снимать по нему полосу не за что.
      press('Ctrl-S');
      expect(cursor(), '..', reason: 'курсор там же, где был');

      // Удалять «..» нечего — команда невыполнима, и окно не откроется.
      expect(press('F8'), isFalse);

      expect(search(), isNotNull, reason: 'полоса на месте');
    });
  });

  test('уход в другой каталог выключает режим', () async {
    press('Ctrl-S');
    type('do');
    expect(pattern(), 'do');

    await panel().openPath('/home/docs');

    expect(search(), isNull, reason: 'образец относится к прежнему списку');
  });

  test('без режима буква по-прежнему прыгает по первой букве', () {
    // Печать сама по себе работает как раньше: `GoToNameCommand` никуда не
    // делась, и быстрый поиск её не заменяет.
    type('n');

    expect(search(), isNull);
    expect(cursor(), 'notes.txt');
  });
}
