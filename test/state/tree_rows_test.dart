import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Источник, чтение которого не заканчивается, пока его не отпустят.
///
/// При запуске вид встаёт раньше, чем панель дочитала восстановленный каталог,
/// и порядок этих двух событий решает всё.
class _HeldProvider extends InMemoryTreeProvider {
  _HeldProvider(super.entries);

  final Completer<void> release = Completer<void>();

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    final inner = super.getDirectoryListing();
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      if (!release.isCompleted) {
        await release.future;
      }
      return op.delegate(inner, params);
    });
  }
}

/// Панель показывает дерево тем же способом, что и список: строками
/// (`docs/spec/panel-node-list.md`, §3).
void main() {
  late InMemoryTreeProvider provider;
  late TestPanel panel;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/lib'),
      FakeEntry.directory('/home/lib/src'),
      FakeEntry.file('/home/lib/app.dart', size: 20),
      FakeEntry.file('/home/main.dart', size: 100),
      FakeEntry.directory('/other'),
    ]);
    panel = testPanel(provider: provider, settings: PanelSettings.defaults('/home'));
    await panel.openPath('/home');
  });

  tearDown(() => panel.dispose());

  List<String> rows() => [for (final entry in panel.session.entries) '${'  ' * entry.level}${entry.name}'];

  /// Даёт фоновому подсчёту дойти до конца.
  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void cursorTo(String name) => panel.setCursorToName(name);

  test('вид просит дерево — и получает строки с глубиной', () async {
    await panel.session.setRows(RowsKind.tree);

    // Корень источника, а под ним раскрытая цепочка до каталога панели:
    // иначе панель показала бы дерево, в котором её самой не видно.
    expect(rows(), ['/', '  home', '    lib', '    main.dart', '  other']);
  });

  test('в дереве курсор встаёт на ветвь своего каталога', () async {
    await panel.session.setRows(RowsKind.tree);

    // Иначе панель окажется на корне — в дереве длиной во весь диск.
    expect(panel.session.currentNode?.name, 'home');
  });

  test('из списка в дерево курсор встаёт на то же, на чём стоял', () async {
    // Живой случай: в списке `/home` стоим на `lib` — в дереве стоим на нём
    // же, а не на каталоге, в котором он лежит.
    cursorTo('lib');

    await panel.session.setRows(RowsKind.tree);

    expect(panel.session.currentNode?.pathString, '/home/lib');
  });

  test('из дерева в список входим в каталог под курсором', () async {
    await panel.session.setRows(RowsKind.tree);
    cursorTo('lib');

    await panel.session.setRows(RowsKind.listing);

    // Курсор на ветви каталога значит «вот этот каталог»: список продолжает
    // ход по дереву, а не пятится на уровень выше.
    expect(panel.session.currentPath, '/home/lib');
    expect(rows(), ['..', 'src', 'app.dart']);
  });

  test('каталог операции при этом прежний — тот, где ветвь лежит', () async {
    await panel.session.setRows(RowsKind.tree);
    cursorTo('lib');

    // Для операций каталог ветви — тот, в котором она лежит: копирование
    // помеченного каталога целится в панель, а не внутрь него
    // (`docs/spec/panel-view-tree.md`, §3).
    expect(panel.session.currentPath, '/home');
  });

  test('обратно в список — каталог той ветви, где стоял курсор', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);
    cursorTo('app.dart');

    await panel.session.setRows(RowsKind.listing);

    // Стояли на `app.dart` в ветви `lib` — список показывает её каталог, а
    // курсор остаётся на том же объекте.
    expect(panel.session.currentPath, '/home/lib');
    expect(rows(), ['..', 'src', 'app.dart']);
    expect(panel.session.currentNode?.name, 'app.dart');
  });

  test('корень каталогом панели не бывает', () async {
    await panel.session.setRows(RowsKind.tree);
    final wasAt = panel.session.currentPath;

    cursorTo('/');

    // Корень ни в чём не лежит: курсор на нём оставляет панель там, где она
    // стояла (`docs/spec/panel-view-tree.md`, §3).
    expect(panel.session.currentPath, wasAt);
  });

  test('ветвь раскрывается и сворачивается по пути', () async {
    await panel.session.setRows(RowsKind.tree);

    await panel.session.setExpanded('/home/lib', expanded: true);
    expect(rows(), ['/', '  home', '    lib', '      src', '      app.dart', '    main.dart', '  other']);

    await panel.session.setExpanded('/home/lib', expanded: false);
    expect(rows(), ['/', '  home', '    lib', '    main.dart', '  other']);
  });

  test('строки знают свою раскрытость', () async {
    await panel.session.setRows(RowsKind.tree);

    final home = panel.session.entries.firstWhere((entry) => entry.name == 'home');
    final other = panel.session.entries.firstWhere((entry) => entry.name == 'other');
    expect(home.isOpen, isTrue);
    expect(other.isOpen, isFalse);
  });

  test('курсор держится за строку, а не за место', () async {
    await panel.session.setRows(RowsKind.tree);
    cursorTo('main.dart');

    await panel.session.setExpanded('/home/lib', expanded: true);

    // Строка уехала вниз — курсор остался на ней.
    expect(panel.session.currentNode?.name, 'main.dart');
  });

  test('каталог операции идёт за курсором и ничего не читает', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    cursorTo('app.dart');
    expect(panel.session.currentPath, '/home/lib');

    cursorTo('home');
    expect(panel.session.currentPath, '/');

    // Панель при этом не читала ни одного каталога: строки уже собраны, а
    // курсор — это курсор (`docs/spec/panel-view-tree.md`, §3).
    expect(panel.session.status, PanelPhase.idle);
    expect(panel.session.busy, isFalse);
  });

  test('пометка в дереве живёт путями и переживает раскрытие', () async {
    await panel.session.setRows(RowsKind.tree);
    cursorTo('main.dart');
    panel.session.toggleCurrentMark();

    await panel.session.setExpanded('/home/lib', expanded: true);

    expect(panel.session.selection.paths, {'/home/main.dart'});
  });

  test('раскрытое переживает смену вида и попадает в настройки', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    // В список и обратно: раскрытое выбрал человек, и терять его незачем.
    await panel.session.setRows(RowsKind.listing);
    await panel.session.setRows(RowsKind.tree);
    expect(rows(), contains('      app.dart'));

    // И то же самое едет в настройки — путями: между запусками узлов не
    // остаётся вовсе.
    expect(panel.session.settings.expanded, contains('/home/lib'));
  });

  test('сохранённое раскрытое возвращается при запуске', () async {
    final restored = testPanel(
      provider: provider,
      settings: PanelSettings(path: '/home', expanded: ['/home/lib', '/home/gone']),
    );
    addTearDown(restored.dispose);
    await restored.openPath('/home');

    await restored.session.setRows(RowsKind.tree);

    // Ветвь раскрыта, а исчезнувший путь пропущен молча.
    expect([
      for (final entry in restored.session.entries) '${'  ' * entry.level}${entry.name}',
    ], contains('      app.dart'));
  });

  test('курсор возвращается на ту же строку, что и был', () async {
    final restored = testPanel(
      provider: provider,
      settings: PanelSettings(path: '/home', expanded: ['/home/lib'], cursorPath: '/home/lib/app.dart'),
    );
    addTearDown(restored.dispose);
    await restored.openPath('/home');

    await restored.session.setRows(RowsKind.tree);

    // Путём, а не именем: в дереве видно много каталогов разом, и одинаковые
    // имена в них — разные объекты.
    expect(restored.session.currentNode?.pathString, '/home/lib/app.dart');
  });

  test('нет такой строки — курсор встаёт на свой каталог', () async {
    final restored = testPanel(
      provider: provider,
      settings: PanelSettings(path: '/home', cursorPath: '/home/gone/deep.txt'),
    );
    addTearDown(restored.dispose);
    await restored.openPath('/home');

    await restored.session.setRows(RowsKind.tree);

    expect(restored.session.currentNode?.name, 'home');
  });

  test('путь курсора уезжает в настройки', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);
    cursorTo('app.dart');

    expect(panel.session.settings.cursorPath, '/home/lib/app.dart');
  });

  test('вид попросил дерево, пока панель читала каталог', () async {
    // Так бывает при запуске: вид встаёт раньше, чем панель дочитала
    // восстановленный каталог. Живьём это выглядело так, что дерево иногда
    // приходило нераскрытым и не раскрывалось вовсе.
    final held = _HeldProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/lib'),
      FakeEntry.file('/home/lib/app.dart', size: 20),
      FakeEntry.directory('/other'),
    ]);
    final fresh = testPanel(provider: held, settings: PanelSettings(path: '/home', expanded: ['/home/lib']));
    addTearDown(fresh.dispose);

    // Чтение каталога уже началось — и вот тут вид просит дерево.
    final opening = fresh.openPath('/home');
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final asking = fresh.session.setRows(RowsKind.tree);
    held.release.complete();
    await opening;
    await asking;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final shown = [for (final entry in fresh.session.entries) '${'  ' * entry.level}${entry.name}'];
    expect(shown, contains('      app.dart'), reason: 'дерево собрано и раскрыто');

    // И раскрывается дальше руками: набор строк — тот, который просили.
    await fresh.session.setExpanded('/other', expanded: true);
    expect(fresh.session.entries.any((entry) => entry.name == 'other' && entry.isOpen), isTrue);
  });

  group('ссылки', () {
    /// Дерево со ссылками: на каталог, на файл и в никуда.
    Future<TestPanel> linked() async {
      final source = InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/real'),
        FakeEntry.directory('/home/real/deep'),
        FakeEntry.file('/home/real/note.txt', size: 5),
        FakeEntry.link('/home/to-dir', '/home/real/deep'),
        FakeEntry.link('/home/to-file', '/home/real/note.txt'),
        FakeEntry.link('/home/broken', '/home/gone'),
      ]);
      final panel = testPanel(provider: source, settings: PanelSettings.defaults('/home'));
      addTearDown(panel.dispose);
      await panel.openPath('/home');
      await panel.session.setRows(RowsKind.tree);
      return panel;
    }

    test('Enter над ссылкой ведёт к каталогу, куда она показывает', () async {
      final panel = await linked();

      expect(await panel.session.followLink('/home/to-dir'), isTrue);

      // Ветви до цели раскрылись, курсор на ней. Сама ссылка при этом не
      // раскрыта: раскрытие увело бы в цикл.
      expect(panel.session.currentNode?.pathString, '/home/real/deep');
      expect([
        for (final entry in panel.session.entries) '${'  ' * entry.level}${entry.name}',
      ], containsAllInOrder(['/', '  home', '    real', '      deep']));
    });

    test('ссылка на файл — курсор на файле', () async {
      final panel = await linked();

      expect(await panel.session.followLink('/home/to-file'), isTrue);

      expect(panel.session.currentNode?.pathString, '/home/real/note.txt');
    });

    test('битая ссылка никуда не ведёт и ничего не двигает', () async {
      final panel = await linked();
      panel.session.setCursorToName('broken');
      final was = panel.session.currentNode?.pathString;

      expect(await panel.session.followLink('/home/broken'), isFalse);

      expect(panel.session.currentNode?.pathString, was);
    });

    test('относительная ссылка считается от своего каталога', () async {
      // Так устроен `/etc` на маке: ссылка на `private/etc`, а не на `/private/etc`.
      final source = InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/real'),
        FakeEntry.file('/home/real/note.txt', size: 5),
        FakeEntry.link('/home/near', 'real'),
        FakeEntry.link('/home/real/up', '../real/note.txt'),
      ]);
      final panel = testPanel(provider: source, settings: PanelSettings.defaults('/home'));
      addTearDown(panel.dispose);
      await panel.openPath('/home');
      await panel.session.setRows(RowsKind.tree);

      expect(await panel.session.followLink('/home/near'), isTrue);
      expect(panel.session.currentNode?.pathString, '/home/real');

      expect(await panel.session.followLink('/home/real/up'), isTrue);
      expect(panel.session.currentNode?.pathString, '/home/real/note.txt', reason: '`..` разобран');
    });

    test('строка не ссылка — идти некуда', () async {
      final panel = await linked();

      expect(await panel.session.followLink('/home/real'), isFalse);
    });
  });

  group('раскрытие вглубь', () {
    test('поддерево раскрывается целиком, одной командой', () async {
      await panel.session.setRows(RowsKind.tree);
      expect(rows(), ['/', '  home', '    lib', '    main.dart', '  other']);

      await panel.session.setExpandedDeep('/home', expanded: true);

      // Всё, что под `home`, — включая вложенное в `lib`.
      expect(rows(), ['/', '  home', '    lib', '      src', '      app.dart', '    main.dart', '  other']);
    });

    test('и сворачивается тоже целиком: внутри тоже свёрнуто', () async {
      await panel.session.setRows(RowsKind.tree);
      await panel.session.setExpandedDeep('/home', expanded: true);

      await panel.session.setExpandedDeep('/home', expanded: false);
      expect(rows(), ['/', '  home', '  other']);
      expect(panel.session.currentNode?.pathString, '/home', reason: 'курсор остался на свёрнутой ветви');

      // Раскрыли обратно на шаг — внутри пусто: свернули и вложенное.
      await panel.session.setExpanded('/home', expanded: true);
      expect(rows(), ['/', '  home', '    lib', '    main.dart', '  other']);
    });

    test('пустой путь — это всё дерево', () async {
      await panel.session.setRows(RowsKind.tree);

      await panel.session.setExpandedDeep('', expanded: true);
      expect(rows(), contains('      app.dart'));

      await panel.session.setExpandedDeep('', expanded: false);
      expect(rows(), ['/'], reason: 'остались одни корни');
      expect(panel.session.currentNode?.name, '/');
    });

    test('раскрытое вглубь уезжает в настройки, как и всякое', () async {
      await panel.session.setRows(RowsKind.tree);
      await panel.session.setExpandedDeep('/home', expanded: true);

      expect(panel.session.settings.expanded, containsAll(['/home', '/home/lib']));
    });
  });

  test('по размеру дерево раскладывается тоже', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    panel.session.sortTo(const SortSpec(column: FsColumn.size));
    expect(rows(), ['/', '  home', '    lib', '      src', '      app.dart', '    main.dart', '  other']);

    panel.session.sortTo(const SortSpec(column: FsColumn.size, direction: SortDirection.descending));

    // Перевернули — и ветви внутри своего уровня переставились.
    expect(rows(), ['/', '  other', '  home', '    lib', '      src', '      app.dart', '    main.dart']);
  });

  test('посчитали ветвь — числа появились и у подкаталогов', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    // Помечаем `home`: обход идёт через `lib` и `src`, и суммы по ним он
    // считает по дороге — выбрасывать их незачем.
    panel.session.setCursorToName('home');
    panel.session.toggleCurrentMark();
    await settle();

    final lib = panel.session.entries.firstWhere((entry) => entry.name == 'lib');
    expect(lib.size, 20, reason: 'ветвь под посчитанной тоже посчитана');
  });

  test('обход кончился — дерево разложилось по новым числам', () async {
    // Две соседние ветви, у которых порядок по размеру отличается от порядка
    // по имени: иначе пересортировку не увидеть.
    final sized = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/big'),
      FakeEntry.file('/home/big/a.bin', size: 500),
      FakeEntry.directory('/home/small'),
      FakeEntry.file('/home/small/b.bin', size: 10),
    ]);
    final fresh = testPanel(provider: sized, settings: PanelSettings.defaults('/home'));
    addTearDown(fresh.dispose);
    await fresh.openPath('/home');
    await fresh.session.setRows(RowsKind.tree);
    fresh.session.sortTo(const SortSpec(column: FsColumn.size));

    List<String> shown() => [for (final entry in fresh.session.entries) '${'  ' * entry.level}${entry.name}'];
    expect(shown(), ['/', '  home', '    big', '    small'], reason: 'размеры неизвестны — разводит имя');

    fresh.session.setCursorToName('home');
    fresh.session.toggleCurrentMark();
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // Числа появились сразу у многих ветвей — порядок обязан их догнать сам,
    // без второго щелчка по заголовку.
    expect(shown(), ['/', '  home', '    small', '    big']);
    // Пометка сдвинула курсор на `big` — он и остался на нём, съехав вниз
    // вместе со строкой.
    expect(fresh.session.currentNode?.name, 'big');
  });

  test('посчитанный каталог встаёт по своему размеру', () async {
    await panel.session.setRows(RowsKind.tree);

    // Считаем `lib`: 20 байт против неизвестного у `other`.
    panel.session.setCursorToName('lib');
    panel.session.toggleCurrentMark();
    await settle();
    expect(panel.session.nodes.firstWhere((node) => node.name == 'lib').size, 20);

    panel.session.sortTo(const SortSpec(column: FsColumn.size, direction: SortDirection.descending));

    // Внутри `home` каталог остаётся выше файла, а `other` и `home` —
    // оба неизвестны, и их разводит доводчик по имени.
    expect(rows(), ['/', '  other', '  home', '    lib', '    main.dart']);
  });

  test('сортировка раскладывает ветви, а не мешает их с содержимым', () async {
    await panel.session.setRows(RowsKind.tree);
    await panel.session.setExpanded('/home/lib', expanded: true);

    panel.session.sortTo(const SortSpec(direction: SortDirection.descending));

    // Порядок переворачивается **внутри** ветвей, а ветви со своим
    // содержимым не перемешиваются; каталоги остаются выше файлов.
    expect(rows(), ['/', '  other', '  home', '    lib', '      src', '      app.dart', '    main.dart']);
  });
}
