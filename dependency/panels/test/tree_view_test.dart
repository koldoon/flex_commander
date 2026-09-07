import 'dart:async';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Дверь, придерживающая подтверждения ядра.
///
/// На петле ядро отвечает в том же кадре, и такого не бывает; на порту —
/// бывает всегда: этой стороне помечено уже пятнадцать объектов, а
/// подтверждение идёт про первый (`docs/spec/client-server.md`, §5.5).
/// Задержка поддельная, как и время в прогоне: кадр её и двигает.
class _LaggingDoor implements Link {
  _LaggingDoor(this._link);

  static const Duration delay = Duration(milliseconds: 100);

  final Link _link;
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast();
  StreamSubscription<CoreEvent>? _listening;

  @override
  Stream<CoreEvent> get events {
    _listening ??= _link.events.listen((event) {
      Future<void>.delayed(delay, () {
        if (!_events.isClosed) {
          _events.add(event);
        }
      });
    });
    return _events.stream;
  }

  @override
  Future<CoreReply> call(CoreRequest request) => _link.call(request);

  @override
  void tell(CoreRequest request) => _link.tell(request);

  @override
  bool get isOpen => _link.isOpen;

  @override
  Future<void> dispose() async {
    await _listening?.cancel();
    await _events.close();
    await _link.dispose();
  }
}

/// Источник со **своей схемой** — как сервер по `ssh` или архив.
///
/// Всё, что не местная файловая система, называет свои объекты адресами со
/// схемой: `sftp:/srv/data`. Дерево спрашивает содержимое именно такими
/// адресами, и это единственное, чем сервер отличается здесь от диска.
class _RemoteProvider extends InMemoryTreeProvider {
  _RemoteProvider(super.entries);

  @override
  String get scheme => 'sftp';

  /// Свой **адрес** источник не понимает — и это не придирка подделки, а то,
  /// как устроены настоящие: `pathOf` отдаёт путь **без схемы**, и разбирает
  /// провайдер тоже путь без схемы. Разбирать адреса умеет корень дерева.
  @override
  Operation<String, FsNode?> resolvePath() {
    final inner = super.resolvePath();
    return TaskOperation<String, FsNode?>((op, path) async {
      if (path.startsWith('$scheme:')) {
        return null;
      }
      return inner.run(path);
    });
  }
}

/// Источник, обход которого идёт заметное время.
///
/// В памяти каталог считается быстрее кадра, и «пока считается» проверить
/// нечем: число появляется сразу и окончательным.
class _SlowWalkProvider extends InMemoryTreeProvider {
  _SlowWalkProvider(super.entries);

  /// Медленна только глубина: ветви, которые читает само дерево, приходят
  /// сразу, а обход идёт вглубь и рассказывает о себе всё это время.
  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    if (dir.name.startsWith('d') || dir.name == 'src') {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.listChildren(dir);
  }
}

/// Дерево каталогов.
///
/// Спецификация — `docs/spec/panel-view-tree.md`.
void main() {
  List<FakeEntry> entries() => [
    FakeEntry.directory('/home'),
    FakeEntry.directory('/home/lib'),
    FakeEntry.directory('/home/lib/src'),
    FakeEntry.directory('/home/test'),
    FakeEntry.directory('/home/.git'),
    FakeEntry.file('/home/main.dart', size: 2048),
    FakeEntry.file('/home/lib/app.dart', size: 1),
    FakeEntry.file('/home/lib/src/panel.dart', size: 1),
    FakeEntry.file('/home/test/panel_test.dart', size: 1),
  ];

  /// То же дерево, но с глубокой ветвью: обход по ней идёт заметное время и всё
  /// это время рассказывает о растущей сумме.
  List<FakeEntry> deepEntries() => [
    ...entries(),
    for (var i = 0; i < 20; i++) ...[
      FakeEntry.directory('/home/lib/d$i'),
      FakeEntry.file('/home/lib/d$i/data.bin', size: 1024),
    ],
  ];

  InMemoryTreeProvider provider() => InMemoryTreeProvider(entries())..home = '/home';

  Future<AppRuntime> open(
    WidgetTester tester, {
    String at = '/home',
    TreeProvider? source,
    PanelSettings? left,
    double height = 600,
  }) async {
    final settings = AppSettings(left: left ?? PanelSettings.defaults(at), right: PanelSettings.defaults('/home'));
    final runtime = await testApp(provider: source ?? provider(), modules: featureModules(), settings: settings);
    await runtime.app.start();

    tester.view.physicalSize = Size(900, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Что показывает плашка над панелью с деревом.
  String plate(WidgetTester tester) =>
      tester
          .widgetList<FcPathPlate>(
            find.descendant(of: find.byType(PanelView).first, matching: find.byType(FcPathPlate)),
          )
          .first
          .path;

  /// Помеченные ветви — по полосе пометки, которой строка и отличается на вид.
  int markedRows(WidgetTester tester) {
    final colors = FcTheme.of(tester.element(find.byType(TreeView))).colors;
    return tester
        .widgetList<ColoredBox>(find.descendant(of: find.byType(TreeView), matching: find.byType(ColoredBox)))
        .where((box) => box.color == colors.markedBar)
        .length;
  }

  /// Что видно в дереве, сверху вниз. Шапка в счёт не идёт — это заголовки
  /// колонок, а не ветви.
  List<String> branches(WidgetTester tester) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.descendant(of: find.byType(TreeView), matching: find.byType(ListView)),
        matching: find.byType(Text),
      ),
    ))
      if ((text.data ?? '').isNotEmpty && (text.data ?? '').codeUnitAt(0) < 0xE000) text.data!,
  ];

  testWidgets('дерево открывается раскрытым до текущего каталога', (tester) async {
    await open(tester, at: '/home/lib');

    // Путь до текущего каталога развёрнут, а он сам раскрыт: видно и соседей,
    // и то, что внутри.
    expect(branches(tester), containsAllInOrder(['home', 'lib', 'src', 'app.dart']));
    expect(branches(tester), contains('test'));
  });

  testWidgets('строка дерева идёт тем же шагом, что строка списка', (tester) async {
    // Слева дерево, справа обычная таблица. Панели видны разом, и шаг строк у
    // них обязан совпадать: иначе рядом стоят два списка, которые не сходятся
    // ни одной строкой (`docs/spec/panel-view-tree.md`, §4).
    final settings = AppSettings(
      left: PanelSettings(path: '/home', view: TreeView.viewId),
      right: PanelSettings.defaults('/home'),
    );
    final runtime = await testApp(provider: provider(), modules: featureModules(), settings: settings);
    await runtime.app.start();
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    double stepBetween(String above, String below) {
      final tops = [above, below].map((name) => tester.getRect(find.text(name).first).top).toList();
      return tops[1] - tops[0];
    }

    // В дереве: `lib` и следующая за ней `test`. В списке: `lib` и `test` же.
    final inTree = stepBetween('lib', 'test');
    final inList = tester.getRect(find.text('test').last).top - tester.getRect(find.text('lib').last).top;

    expect(inTree, greaterThan(0));
    expect(inTree, closeTo(inList, 0.01), reason: 'шаг строк один и тот же');
  });

  testWidgets('знак раскрытия только у каталогов', (tester) async {
    await open(tester);

    List<String> glyphsIn(String name) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
          matching: find.byType(Text),
        ),
      ))
        if ((text.data ?? '').isNotEmpty && text.data!.codeUnitAt(0) >= 0xE000) text.data!,
    ];

    final icons = FcTheme.of(tester.element(find.byType(TreeView))).icons;
    final closed = String.fromCharCode(icons.branchClosed.codePoint);

    expect(glyphsIn('lib'), contains(closed), reason: 'у каталога знак есть');
    expect(glyphsIn('main.dart'), isNot(contains(closed)), reason: 'у файла внутри ничего нет — и знака тоже');
  });

  testWidgets('знак ветви ложится на квадрат значка родителя', (tester) async {
    await open(tester, at: '/home/lib');

    // Значок объекта и знак раскрытия — один и тот же квадрат, а знак стоит
    // вплотную слева. Значит, шаг вглубь равен этому квадрату: у дочерней
    // ветви знак приходится ровно туда, где у родительской значок.
    Rect iconOf(String name) => tester.getRect(
      find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
        matching: find.byType(FileTypeIcon),
      ),
    );

    final metrics = FcTheme.of(tester.element(find.byType(TreeView))).metrics;
    final parent = iconOf('lib');
    final child = iconOf('src');

    // Знак дочерней ветви стоит сразу перед её значком, на ширину квадрата
    // с просветом: середина знака приходится на середину значка родителя.
    expect(
      child.left - parent.left,
      closeTo(parent.width + metrics.treeMarkGap, 0.01),
      reason: 'знак ребёнка встал на значок родителя',
    );
    expect(child.width, closeTo(parent.width, 0.01));
  });

  testWidgets('в дереве и каталоги, и файлы', (tester) async {
    await open(tester);

    expect(branches(tester), contains('lib'));
    expect(branches(tester), contains('main.dart'), reason: 'половина ответа «что где лежит» — это файлы');
  });

  testWidgets('стрелка водит курсор и больше ничего не трогает', (tester) async {
    final runtime = await open(tester);
    final before = branches(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();

    expect(branches(tester), before, reason: 'ветвь сама не раскрылась');
    expect(runtime.app.left.view, TreeView.viewId, reason: 'и вид остался деревом');
  });

  testWidgets('каталог панели идёт за курсором', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;
    // Курсор стоит на ветви `lib`, а сама она лежит в `/home` — туда панель и
    // встала: каталог выводится из курсора сразу, а не с первым его шагом
    // (`docs/spec/panel-node-list.md`, §3).
    expect(panel.currentPath, '/home');

    // Курсор на самой ветви `lib` — под ним `src`. Спускаемся, раскрываем и
    // уходим курсором внутрь.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();

    expect(panel.currentPath, '/home/lib/src', reason: 'каталог панели — тот, в котором ветвь под курсором');
    expect(plate(tester), '/home/lib/src', reason: 'и плашка говорит о нём же');
    expect(panel.currentEntry?.name, 'panel.dart', reason: 'курсор панели — на том же объекте');
    expect(panel.busy, isFalse, reason: 'панель за это не платит занятостью');

    // И обратно: курсор вышел из ветви — панель вышла с ним.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();

    expect(panel.currentPath, '/home/lib', reason: 'курсор вернулся на `src`, а тот лежит в `lib`');
  });

  testWidgets('на корне панель остаётся там, где стояла', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Спускаемся внутрь, чтобы панель встала во вполне определённый каталог.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/home/lib');

    runtime.commands.dispatch(KeyCombination.parse('Home'));
    await tester.pumpAndSettle();

    expect(branches(tester).first, '/', reason: 'курсор на корне источника');
    expect(panel.currentPath, '/home/lib', reason: 'корень ни в каком каталоге не лежит');
  });

  testWidgets('Enter раскрывает ветвь и сворачивает обратно', (tester) async {
    final runtime = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    final before = branches(tester).length;

    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, greaterThan(before), reason: 'ветвь раскрылась');

    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, before, reason: 'и свернулась обратно');
  });

  testWidgets('Left на файле уводит в его каталог, а следующий — сворачивает', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Курсор на ветви `lib`; спускаемся на файл внутри неё.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.currentEntry?.name, 'app.dart');

    // Первый `Left` — к каталогу, в котором файл лежит.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();

    expect(panel.currentEntry?.name, 'lib', reason: 'курсор ушёл на саму ветвь');
    expect(panel.currentPath, '/home', reason: 'а `lib` лежит в корне');
    expect(branches(tester), contains('app.dart'), reason: 'ветвь при этом не свернулась');

    // Второй — сворачивает её.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();

    expect(branches(tester), isNot(contains('app.dart')));
    expect(panel.currentEntry?.name, 'lib', reason: 'курсор остался на ней же');
  });

  testWidgets('Right и Left делают то же самое', (tester) async {
    final runtime = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    final before = branches(tester).length;

    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, greaterThan(before));

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    expect(branches(tester).length, before);
  });

  testWidgets('Space помечает ветвь под курсором и шагает вниз', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Курсор на ветви `lib`; спускаемся на `src` и помечаем его.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    expect(panel.markedPaths, {'/home/lib/src'}, reason: 'помечена ветвь под курсором');
    expect(markedRows(tester), 1, reason: 'и это видно в дереве');

    // Обратно вверх и ещё раз — пометка снимается.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    expect(panel.markedPaths, isEmpty);
    expect(markedRows(tester), 0);
  });

  testWidgets('пометка из разных ветвей складывается', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Помечаем `src` в `lib` — курсор от пометки уходит на `app.dart`…
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    // …уходим курсором в соседнюю ветвь и помечаем там.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/home/test', reason: 'курсор ушёл в соседнюю ветвь');

    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();

    expect(panel.markedPaths, {'/home/lib/src', '/home/test/panel_test.dart'});
    expect(markedRows(tester), 2, reason: 'обе ветви показывают пометку');
  });

  testWidgets('дерево работает и на источнике со своей схемой', (tester) async {
    // Найдено на живом: на `ssh` дерево не показывало ничего. Ядро тут ни при
    // чём — контракт один; расходились **пути**: вид спрашивает адресами
    // строк, а источник понимает свои пути, и схема в начале была для него
    // именем каталога (`docs/spec/panel-view-tree.md`, §5).
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    final runtime = await testApp(
      provider: _RemoteProvider(entries())..home = '/home',
      modules: featureModules(),
      settings: settings,
    );
    await runtime.app.start();
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();

    expect(branches(tester), containsAll(['home', 'lib', 'main.dart']), reason: 'ветви прочитались');
    // Корень сервера — такой же корень: у адреса последнее звено пусто, и без
    // правила верхняя ветвь стояла безымянной.
    expect(branches(tester).first, '/', reason: 'корень подписан');

    // И ходит по нему так же: раскрытие читает следующую ветвь.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();

    expect(branches(tester), contains('app.dart'), reason: 'ветвь раскрылась и прочиталась');
  });

  testWidgets('пометка не теряется, пока панель догоняет курсор', (tester) async {
    // Найдено на живом: в дереве помечают каталоги, удерживая `Space`, и после
    // полутора десятков помеченное начинает гаснуть, а дерево мерцать.
    //
    // Причина — в отставании подтверждений. Каталог панели идёт за курсором
    // дерева, и пока панель туда добирается, она говорит про **прежний**
    // каталог. Дерево принимало это за «панель ушла сама» и разворачивалось
    // обратно, уводя курсор назад, — а следующий `Space` снимал пометку,
    // которую сам же и поставил (`docs/spec/panel-view-tree.md`, §3).
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    final runtime = await testApp(
      provider: provider(),
      modules: featureModules(),
      settings: settings,
      door: _LaggingDoor.new,
    );
    await runtime.app.start();
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(TreeView.viewId);
    await tester.pumpAndSettle();

    final panel = runtime.app.left;
    // Раскрываем `lib`: дальше курсор пойдёт через границу каталогов, и каждый
    // шаг заставит панель догонять.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();

    const presses = 4;
    for (var i = 0; i < presses; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Space'));
      // Кадр — и следующее нажатие: клавиша повторяется быстрее, чем ядро
      // успевает подтвердить.
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(panel.markedPaths, hasLength(presses), reason: 'сколько нажали, столько и помечено');
  });

  testWidgets('зажатый Space помечает подряд и ничего не теряет', (tester) async {
    // Найдено на живом: пометка ставится сразу, а подтверждения ядра приходят
    // с отставанием — и собранный поверх опоздавшего набор терял уже
    // помеченное (`docs/spec/client-server.md`, §5.5).
    final runtime = await open(tester);
    final panel = runtime.app.left;

    // Раскрываем обе ветви, чтобы помечать было что.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();

    // Курсор стоит на `lib`, ниже него — `src`, `app.dart`, `test`,
    // `main.dart`: пять нажатий, пять пометок. Шестое пришлось бы на последнюю
    // строку второй раз и сняло бы её.
    const presses = 5;
    for (var i = 0; i < presses; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Space'));
      // Кадрами, а не с успокоением: клавиша повторяется быстрее, чем ядро
      // успевает подтвердить.
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(panel.markedPaths, hasLength(presses), reason: 'сколько нажали, столько и помечено');
  });

  testWidgets('пометка из двух ветвей доходит до окна копирования', (tester) async {
    final runtime = await open(tester, at: '/home/lib');
    final panel = runtime.app.left;

    // Помечаем `src` в `lib` и `panel_test.dart` в `test` — как в проверке
    // выше, но теперь спрашиваем окно (`docs/spec/operation-targets.md`, §7).
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();
    expect(panel.markedPaths, {'/home/lib/src', '/home/test/panel_test.dart'});

    runtime.commands.dispatch(KeyCombination.parse('F5'));
    await tester.pumpAndSettle();

    expect(find.text('Copy 2 items'), findsOneWidget, reason: 'считается всё помеченное');

    // «Откуда» дописывается после показа окна: каталогов два, и вместо пути
    // сказано их число.
    final source = tester.widgetList<FcTextField>(find.byType(FcTextField)).firstWhere((field) => !field.enabled);
    expect(source.controller.text, '2 sources');
  });

  /// Что написано в строке ветви справа от имени; '' — ничего.
  String sizeOf(WidgetTester tester, String name) {
    final row = find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
    final texts = [
      for (final text in tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text))))
        text.data ?? '',
    ];
    // Последняя строка — размер, если он есть: имя стоит перед ним.
    final at = texts.indexOf(name);
    return at >= 0 && at + 1 < texts.length ? texts[at + 1] : '';
  }

  testWidgets('размер файла виден сразу, а непосчитанного каталога — нет', (tester) async {
    await open(tester);

    expect(sizeOf(tester, 'main.dart'), '2.0K');
    expect(sizeOf(tester, 'lib'), '', reason: 'каталог не считали — и числа нет');
  });

  testWidgets('пометил каталог — размер посчитался', (tester) async {
    final runtime = await open(tester);

    // Курсор на `lib`; помечаем — и очередь панели идёт считать
    // (`docs/spec/directory-sizes.md`).
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(sizeOf(tester, 'lib'), isNotEmpty, reason: 'посчитанный каталог показывает размер');
  });

  testWidgets('помеченная ветвь считается на глазах, где бы ни стоял курсор', (tester) async {
    final runtime = await open(tester, source: _SlowWalkProvider(deepEntries())..home = '/home');

    /// Кадры без `pumpAndSettle`: тот дождался бы конца обхода, а проверить
    /// надо именно то, что видно **пока** он идёт.
    Future<void> tick([int times = 3]) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    // Помечаем `lib` и уходим курсором в другую ветвь: список панели теперь про
    // `test`, и про `lib` он молчит.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tick();

    expect(runtime.app.left.markedSizeIsFinal, isFalse, reason: 'обход ещё идёт — иначе стенд ни о чём');

    await tick(60);

    // Живой счётчик, а не прочерк до самого конца обхода.
    expect(sizeOf(tester, 'lib'), isNotEmpty);

    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  });

  testWidgets('растущее число не сползает на соседнюю строку', (tester) async {
    final runtime = await open(tester, source: _SlowWalkProvider(deepEntries())..home = '/home');

    Future<void> tick([int times = 3]) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    // Раскрываем `lib` и помечаем её: курсор шагает вниз, на её же ребёнка, и
    // панель уходит внутрь — список под размерами меняется на ходу.
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tick(10);

    expect(runtime.app.left.markedSizeIsFinal, isFalse, reason: 'обход ещё идёт — иначе стенд ни о чём');

    // Размеры едут номерами строк, а список под ними сменился — число
    // помеченного каталога легко приписывается чужой строке.
    expect(sizeOf(tester, 'lib'), isNotEmpty, reason: 'помеченное считается');
    expect(sizeOf(tester, 'd0'), isNot(sizeOf(tester, 'lib')), reason: 'у подкаталога своё число, а не сумма родителя');

    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  });

  testWidgets('число не мигает пустотой, пока идёт счёт', (tester) async {
    final runtime = await open(tester, source: _SlowWalkProvider(deepEntries())..home = '/home');

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pump(const Duration(milliseconds: 10));
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(sizeOf(tester, 'lib'), isNotEmpty, reason: 'число появилось');

    // Кадр за кадром: раз показав число, ветвь не имеет права показать пустоту
    // до конца счёта — а ядро молчит о ней всякий раз, когда обход начинается
    // заново.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (!runtime.app.left.markedSizeIsFinal) {
        expect(sizeOf(tester, 'lib'), isNotEmpty, reason: 'кадр $i');
      }
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  });

  testWidgets('идущий подсчёт не мешает крутить колесо', (tester) async {
    // Живой дефект: пока считается большой каталог, вид не давал промотать
    // себя дальше курсора — размеры приходят новым списком строк по нескольку
    // раз в секунду, и на каждый приход вид возвращался к курсору.
    final runtime = await open(tester, source: _SlowWalkProvider(deepEntries())..home = '/home', height: 300);

    Future<void> tick([int times = 3]) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tick();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tick(5);
    expect(runtime.app.left.markedSizeIsFinal, isFalse, reason: 'обход ещё идёт — иначе стенд ни о чём');

    // Крутим вниз: курсор остаётся наверху и уходит за верхний край.
    final list = find.byType(ListView).first;
    double offset() => tester.widget<ListView>(list).controller!.offset;
    await tester.drag(list, const Offset(0, -160));
    await tester.pumpAndSettle();
    final scrolled = offset();
    expect(scrolled, greaterThan(100), reason: 'вид промотался');

    // И пока обход рассказывает о себе, вид стоит там, куда его поставили.
    await tick(10);
    expect(offset(), closeTo(scrolled, 1));

    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  });

  testWidgets('у подкаталогов посчитанного каталога размер тоже виден', (tester) async {
    final runtime = await open(tester);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Space'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Возвращаемся на `lib` и раскрываем её.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Обход и так прошёл через `src` — сумма по нему известна, и прятать её
    // незачем.
    expect(sizeOf(tester, 'src'), isNotEmpty);
  });

  testWidgets('после запуска вид стоит там же, где стоял', (tester) async {
    // Длинное дерево: экрана на него не хватает, и промотка видна.
    final deep = [
      FakeEntry.directory('/home'),
      for (var i = 0; i < 60; i++) FakeEntry.file('/home/file-$i.txt', size: 10),
    ];
    final runtime = await open(
      tester,
      source: InMemoryTreeProvider(deep)..home = '/home',
      left: PanelSettings(path: '/home', expanded: ['/', '/home'], cursorPath: '/home/file-59.txt'),
    );
    await tester.pumpAndSettle();

    // Курсор глубоко внизу — и он виден целиком, а не разрезан нижним краем.
    // Строка дерева, а не строка состояния: имя под курсором видно в обеих.
    final row = find.descendant(of: find.byType(TreeView), matching: find.text('file-59.txt'));
    expect(row, findsOneWidget);
    final panelBox = tester.getRect(find.byType(TreeView));
    final rowBox = tester.getRect(row);
    expect(rowBox.top, greaterThanOrEqualTo(panelBox.top));
    expect(rowBox.bottom, lessThanOrEqualTo(panelBox.bottom));
    expect(runtime.app.left.currentEntry?.name, 'file-59.txt');
  });

  testWidgets('сохранённая прокрутка возвращает вид на то же место', (tester) async {
    final deep = [
      FakeEntry.directory('/home'),
      for (var i = 0; i < 60; i++) FakeEntry.file('/home/file-$i.txt', size: 10),
    ];
    // Двадцать пять строк вниз: курсор при этом виден, и правила подмотки не
    // нужны — вид просто встаёт там, где стоял.
    final runtime = await open(
      tester,
      source: InMemoryTreeProvider(deep)..home = '/home',
      left: PanelSettings(path: '/home', expanded: ['/', '/home'], cursorPath: '/home/file-30.txt', scroll: 25 * 20.0),
    );
    await tester.pumpAndSettle();

    // Первой строкой — та, что была первой при закрытии.
    final first = find.descendant(of: find.byType(TreeView), matching: find.text('file-23.txt'));
    expect(first, findsOneWidget);
    final list = tester.getRect(find.byType(ListView).first);
    // С запасом на поправки внутри строки — но много меньше шага строки:
    // соседнюю с ней так не спутать.
    expect(tester.getRect(first).top, closeTo(list.top, 6));
    expect(runtime.app.left.currentEntry?.name, 'file-30.txt');
  });

  testWidgets('курсор доходит до нижнего края', (tester) async {
    final deep = [
      FakeEntry.directory('/home'),
      for (var i = 0; i < 60; i++) FakeEntry.file('/home/file-$i.txt', size: 10),
    ];
    final runtime = await open(
      tester,
      source: InMemoryTreeProvider(deep)..home = '/home',
      left: PanelSettings(path: '/home', expanded: ['/', '/home']),
    );
    await tester.pumpAndSettle();

    // Ведём курсор вниз, пока он не уйдёт за край и не потянет вид за собой.
    for (var i = 0; i < 30; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
    }
    await tester.pumpAndSettle();

    final name = runtime.app.left.currentEntry!.name;
    final row = find.descendant(of: find.byType(TreeView), matching: find.text(name));
    final list = tester.getRect(find.byType(ListView).first);

    // Строка под курсором стоит **у самого низа**: подмотка минимальная, и
    // лишней строки под ней не остаётся.
    expect(tester.getRect(row).bottom, closeTo(list.bottom, 6));
  });

  testWidgets('перестановка не двигает строку под курсором', (tester) async {
    // Имена и размеры расходятся нарочно: сортировка по размеру переставляет
    // список наоборот, и строке под курсором есть куда уехать.
    final deep = [
      FakeEntry.directory('/home'),
      for (var i = 0; i < 60; i++)
        FakeEntry.file('/home/file-${i.toString().padLeft(2, '0')}.txt', size: (60 - i) * 10),
    ];
    final runtime = await open(
      tester,
      source: InMemoryTreeProvider(deep)..home = '/home',
      left: PanelSettings(path: '/home', expanded: ['/', '/home']),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
    }
    await tester.pumpAndSettle();
    // И назад от нижнего края: у края любая подмотка вернула бы строку на то
    // же место сама, и проверять было бы нечего.
    for (var i = 0; i < 5; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Up'));
    }
    await tester.pumpAndSettle();

    final name = runtime.app.left.currentEntry!.name;
    Finder row() => find.descendant(of: find.byType(TreeView), matching: find.text(name));
    final was = tester.getRect(row()).top;

    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Size')));
    await tester.pumpAndSettle();

    // Строка уехала на другое место в списке — но не на экране: вид уехал
    // вместе с ней (`docs/spec/panel-views.md`, §9).
    expect(runtime.app.left.currentEntry?.name, name);
    expect(tester.getRect(row()).top, closeTo(was, 1));
  });

  testWidgets('настройку сняли — перестановка снова уводит строку', (tester) async {
    final deep = [
      FakeEntry.directory('/home'),
      for (var i = 0; i < 60; i++)
        FakeEntry.file('/home/file-${i.toString().padLeft(2, '0')}.txt', size: (60 - i) * 10),
    ];
    final runtime = await open(
      tester,
      source: InMemoryTreeProvider(deep)..home = '/home',
      left: PanelSettings(path: '/home', expanded: ['/', '/home']),
    );
    await tester.pumpAndSettle();
    // Флажок спрашивается в момент подмотки — снять его можно и на ходу.
    runtime.app.settings.modules.scope(Panels().id).section(PanelsSettings.new).cursorHoldsPlace = false;

    for (var i = 0; i < 30; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Down'));
    }
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      runtime.commands.dispatch(KeyCombination.parse('Up'));
    }
    await tester.pumpAndSettle();

    final name = runtime.app.left.currentEntry!.name;
    Finder row() => find.descendant(of: find.byType(TreeView), matching: find.text(name));
    final was = tester.getRect(row()).top;

    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Size')));
    await tester.pumpAndSettle();

    // Прежнее поведение: список стоит, строка уезжает, и вид догоняет её
    // минимальной подмоткой — к тому краю, за который она вышла.
    final list = tester.getRect(find.byType(ListView).first);
    expect(runtime.app.left.currentEntry?.name, name);
    expect(tester.getRect(row()).top, isNot(closeTo(was, 1)));
    expect(tester.getRect(row()).bottom, closeTo(list.bottom, 6));
  });

  testWidgets('щелчок по заголовку сортирует дерево', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();

    final before = branches(tester);
    expect(before, containsAllInOrder(['lib', 'test', 'main.dart']));

    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Tree')));
    await tester.pumpAndSettle();

    // Тот же порядок, только наоборот, — и внутри ветвей, а не вперемешку:
    // каталоги остаются выше файлов.
    expect(branches(tester), containsAllInOrder(['test', 'lib', 'main.dart']));
    expect(panel.sort.column, FsColumn.name);
    expect(panel.sort.direction, SortDirection.descending);
  });

  testWidgets('сортировка в дереве — та же, что в списке', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;

    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Size')));
    await tester.pumpAndSettle();

    expect(panel.sort.column, FsColumn.size, reason: 'правило одно на панель');

    // Переключились в список — порядок тот же: правило панельное.
    await panel.setView('table');
    await tester.pumpAndSettle();
    expect(panel.sort.column, FsColumn.size);
  });

  testWidgets('курсор остаётся на той же ветви при смене порядка', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.currentEntry?.name, 'lib');

    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Tree')));
    await tester.pumpAndSettle();

    // Строка уехала — курсор остался на ней.
    expect(panel.currentEntry?.name, 'lib');
  });

  testWidgets('щелчок по «Size» переставляет строки по размеру', (tester) async {
    final sizes = [
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.txt', size: 30),
      FakeEntry.file('/home/b.txt', size: 10),
      FakeEntry.file('/home/c.txt', size: 20),
    ];
    final runtime = await open(
      tester,
      source: InMemoryTreeProvider(sizes)..home = '/home',
      left: PanelSettings(path: '/home', expanded: ['/', '/home']),
    );
    await tester.pumpAndSettle();
    expect(branches(tester), containsAllInOrder(['a.txt', 'b.txt', 'c.txt']));

    await tester.tap(find.descendant(of: find.byType(TreeView), matching: find.text('Size')));
    await tester.pumpAndSettle();

    expect(runtime.app.left.sort.column, FsColumn.size);
    expect(branches(tester), containsAllInOrder(['b.txt', 'c.txt', 'a.txt']));
  });

  testWidgets('колонку размера выключают в настройках вида', (tester) async {
    final runtime = await open(tester);
    expect(sizeOf(tester, 'main.dart'), '2.0K');

    // Тем же путём, каким это делает человек: окно выбора вида, флажок под
    // списком, «Show» (`docs/spec/panel-views.md`, §8).
    runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
    await tester.pumpAndSettle();
    // По подписи флажка: «Size» есть и в шапке таблицы соседней панели, а
    // попасть надо в тот, что в окне.
    await tester.tap(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Size')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FcButton, 'Show'));
    await tester.pumpAndSettle();

    expect(sizeOf(tester, 'main.dart'), '', reason: 'выключенной колонки нет вовсе');
  });

  testWidgets('флажки колонок стоят с обычным просветом', (tester) async {
    final runtime = await open(tester);
    runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
    await tester.pumpAndSettle();

    final boxes = find.byType(FcCheckbox);
    expect(boxes, findsNWidgets(2));
    final first = tester.getRect(boxes.at(0));
    final second = tester.getRect(boxes.at(1));

    // Тот же просвет, что между флажками в любом другом окне: это
    // самостоятельные управления, а не строки одного поля
    // (`docs/widgets.md`).
    final metrics = FcTheme.of(tester.element(boxes.at(0))).metrics;
    expect(second.top - first.bottom, closeTo(metrics.dialogGap, 0.5));
  });

  testWidgets('скрытые каталоги приходят вместе с Cmd-H', (tester) async {
    final runtime = await open(tester);
    expect(branches(tester), isNot(contains('.git')));

    await runtime.app.left.setShowHidden(true);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(branches(tester), contains('.git'));
  });
}
