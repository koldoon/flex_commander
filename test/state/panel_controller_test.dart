import 'package:flex_commander/model/panel/column_spec.dart';
import 'package:flex_commander/model/panel/sort_spec.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

void main() {
  late InMemoryTreeProvider provider;
  late PanelController panel;

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 100),
      FakeEntry.file('/home/report.xlsx', size: 2048),
      FakeEntry.file('/home/.hidden', size: 1),
      FakeEntry.file('/home/docs/readme.md', size: 10),
      FakeEntry.link('/home/link-to-bin', '/home/bin'),
    ]);
    panel = PanelController(provider: provider, settings: PanelSettings.defaults('/home'));
  });

  tearDown(() => panel.dispose());

  List<String> namesOf(PanelController panel) => panel.nodes.map((n) => n.name).toList();

  group('открытие каталога', () {
    test('читает содержимое и сортирует его', () async {
      expect(await panel.openPath('/home'), isTrue);

      expect(panel.status, PanelStatus.idle);
      expect(panel.directory?.pathString, '/home');
      // "..", затем каталоги (ссылка на каталог тоже), затем файлы.
      expect(namesOf(panel), ['..', 'bin', 'docs', 'link-to-bin', 'notes.txt', 'report.xlsx']);
      expect(panel.cursorIndex, 0);
    });

    test('скрытые объекты показываются по флагу', () async {
      await panel.openPath('/home');
      expect(namesOf(panel), isNot(contains('.hidden')));

      await panel.setShowHidden(true);
      expect(namesOf(panel), contains('.hidden'));
    });

    test('несуществующий путь не открывается', () async {
      expect(await panel.openPath('/nowhere'), isFalse);
      expect(panel.directory, isNull);
    });

    test('путь к файлу не открывается', () async {
      expect(await panel.openPath('/home/notes.txt'), isFalse);
    });

    test('ошибка чтения оставляет панель в прежнем каталоге', () async {
      await panel.openPath('/home');
      provider.denied['/home/docs'] = const FsError('/home/docs', FsErrorKind.permissionDenied);

      final docs = panel.nodes.firstWhere((n) => n.name == 'docs') as DirectoryNode;
      await panel.open(docs);

      expect(panel.status, PanelStatus.error);
      expect(panel.error?.kind, FsErrorKind.permissionDenied);
      expect(panel.directory?.pathString, '/home');
      expect(panel.statusText, contains('Permission denied'));
      expect(panel.busy, isFalse);
    });

    test('во время чтения панель занята', () async {
      final future = panel.openPath('/home');
      expect(panel.busy, isTrue);
      expect(panel.statusText, 'Loading…');

      await future;
      expect(panel.busy, isFalse);
      expect(panel.statusText, isNull);
    });

    test('результат устаревшего чтения не применяется', () async {
      await panel.openPath('/home');
      final docs = panel.nodes.firstWhere((n) => n.name == 'docs') as DirectoryNode;
      final bin = panel.nodes.firstWhere((n) => n.name == 'bin') as DirectoryNode;

      final first = panel.open(docs);
      final second = panel.open(bin);
      await Future.wait([first, second]);

      expect(panel.directory?.pathString, '/home/bin');
      expect(panel.busy, isFalse);
    });
  });

  group('навигация', () {
    setUp(() => panel.openPath('/home'));

    test('вход в каталог под курсором', () async {
      panel.setCursorToName('docs');
      expect(await panel.enterCurrent(), isNull);

      expect(panel.directory?.pathString, '/home/docs');
      expect(namesOf(panel), ['..', 'readme.md']);
    });

    test('вход в ссылку показывает путь через саму ссылку', () async {
      panel.setCursorToName('link-to-bin');
      expect(await panel.enterCurrent(), isNull);

      // Содержимое берётся из цели, но пользователь пришёл через ссылку —
      // её и должен видеть в заголовке панели.
      expect(panel.directory?.pathString, '/home/link-to-bin');
    });

    test('из каталога, открытого по ссылке, наверх ведёт к самой ссылке', () async {
      panel.setCursorToName('link-to-bin');
      await panel.enterCurrent();

      await panel.goUp();

      // Не в /home/bin/.. и не в физического родителя цели, а туда,
      // откуда пользователь пришёл.
      expect(panel.directory?.pathString, '/home');
      expect(panel.currentNode?.name, 'link-to-bin');
    });

    test('".." внутри ссылки работает так же, как переход наверх', () async {
      panel.setCursorToName('link-to-bin');
      await panel.enterCurrent();

      panel.setCursorToFirst();
      expect(panel.currentNode, isA<ParentDirNode>());
      await panel.enterCurrent();

      expect(panel.directory?.pathString, '/home');
      expect(panel.currentNode?.name, 'link-to-bin');
    });

    test('путь через ссылку восстанавливается из настроек', () async {
      expect(await panel.openPath('/home/link-to-bin'), isTrue);

      expect(panel.directory?.pathString, '/home/link-to-bin');
      expect(panel.settings.path, '/home/link-to-bin');
    });

    test('файл возвращается вызывающему коду', () async {
      panel.setCursorToName('notes.txt');
      final node = await panel.enterCurrent();

      expect(node?.name, 'notes.txt');
      expect(panel.directory?.pathString, '/home');
    });

    test('".." поднимает на уровень вверх', () async {
      await panel.openPath('/home/docs');
      panel.setCursorIndex(0);
      expect(panel.currentNode, isA<ParentDirNode>());

      await panel.enterCurrent();
      expect(panel.directory?.pathString, '/home');
    });

    test('после подъёма курсор стоит на покинутом каталоге', () async {
      panel.setCursorToName('docs');
      await panel.enterCurrent();
      await panel.goUp();

      expect(panel.currentNode?.name, 'docs');
    });

    test('в корне подниматься некуда', () async {
      await panel.openPath('/');
      await panel.goUp();

      expect(panel.directory?.pathString, '/');
    });

    test('возврат в посещённый каталог восстанавливает курсор', () async {
      panel.setCursorToName('report.xlsx');
      await panel.openPath('/home/docs');
      await panel.openPath('/home');

      expect(panel.currentNode?.name, 'report.xlsx');
    });

    test('подъём наверх важнее запомненного курсора', () async {
      // Курсор был на файле, но пользователь ушёл в каталог и вернулся "вверх":
      // ожидание в таком случае — курсор на покинутом каталоге.
      panel.setCursorToName('report.xlsx');
      final docs = panel.nodes.firstWhere((n) => n.name == 'docs') as DirectoryNode;

      await panel.open(docs);
      await panel.goUp();

      expect(panel.currentNode?.name, 'docs');
    });
  });

  group('курсор', () {
    setUp(() => panel.openPath('/home'));

    test('движение ограничено границами списка', () {
      panel.moveCursor(-5);
      expect(panel.cursorIndex, 0);

      panel.moveCursor(100);
      expect(panel.cursorIndex, panel.nodes.length - 1);
    });

    test('страница считается от числа видимых строк', () {
      panel.pageSize = 3;
      panel.moveCursorPage(1);
      expect(panel.cursorIndex, 2);

      panel.moveCursorPage(-1);
      expect(panel.cursorIndex, 0);
    });

    test('первый и последний', () {
      panel.setCursorToLast();
      expect(panel.currentNode?.name, 'report.xlsx');

      panel.setCursorToFirst();
      expect(panel.currentNode?.name, '..');
    });

    test('несуществующее имя не двигает курсор', () {
      panel.setCursorToName('docs');
      panel.setCursorToName('нет такого файла');
      expect(panel.currentNode?.name, 'docs');
    });
  });

  group('пометка', () {
    setUp(() => panel.openPath('/home'));

    test('пометка сдвигает курсор вниз', () {
      panel.setCursorToName('notes.txt');
      panel.toggleCurrentMark();

      expect(panel.selection.names, {'notes.txt'});
      expect(panel.currentNode?.name, 'report.xlsx');
    });

    test('".." не помечается', () {
      panel.setCursorToFirst();
      panel.toggleCurrentMark();

      expect(panel.selection.isEmpty, isTrue);
    });

    test('суммарный размер считает только известные размеры', () {
      panel.markAll();

      expect(panel.selection.length, panel.nodes.length - 1); // без ".."
      expect(panel.selection.totalSize, 2148); // 100 + 2048, каталоги не в счёт
    });

    test('открытие другого каталога снимает пометку', () async {
      panel.markAll();
      await panel.openPath('/home/docs');

      expect(panel.selection.isEmpty, isTrue);
    });
  });

  group('перечитывание', () {
    setUp(() => panel.openPath('/home'));

    test('сохраняет курсор и пометку по именам', () async {
      panel.setCursorToName('notes.txt');
      panel.selection.add(panel.nodes.firstWhere((n) => n.name == 'report.xlsx'));

      await panel.reload();

      expect(panel.currentNode?.name, 'notes.txt');
      expect(panel.selection.names, {'report.xlsx'});
      // Узлы после перечитывания — новые экземпляры.
      expect(panel.selection.nodes.first, same(panel.nodes.firstWhere((n) => n.name == 'report.xlsx')));
    });

    test('исчезнувший объект под курсором заменяется соседним', () async {
      panel.setCursorToName('report.xlsx');
      final index = panel.cursorIndex;
      provider.remove('/home/report.xlsx');

      await panel.reload();

      expect(panel.currentNode?.name, isNot('report.xlsx'));
      expect(panel.cursorIndex, lessThanOrEqualTo(index));
    });

    test('исчезнувшие помеченные объекты отбрасываются', () async {
      panel.markAll();
      provider.remove('/home/notes.txt');

      await panel.reload();

      expect(panel.selection.names, isNot(contains('notes.txt')));
    });
  });

  group('сортировка', () {
    setUp(() => panel.openPath('/home'));

    test('клик по колонке меняет направление', () {
      expect(panel.sort.direction, SortDirection.ascending);

      panel.sortBy(FsColumn.name);
      expect(panel.sort.direction, SortDirection.descending);
      expect(namesOf(panel), ['..', 'link-to-bin', 'docs', 'bin', 'report.xlsx', 'notes.txt']);
    });

    test('курсор остаётся на том же объекте', () {
      panel.setCursorToName('notes.txt');
      panel.sortBy(FsColumn.size);

      expect(panel.currentNode?.name, 'notes.txt');
    });

    test('по колонке иконки сортировать нельзя', () {
      final before = panel.sort;
      panel.sortBy(FsColumn.icon);

      expect(panel.sort, before);
    });
  });

  test('настройки панели отражают текущее состояние', () async {
    await panel.openPath('/home/docs');
    panel.sortBy(FsColumn.size);
    panel.setColumnLayout(panel.columns.toggleVisible(FsColumn.attributes));

    final settings = panel.settings;
    expect(settings.path, '/home/docs');
    expect(settings.sort.column, FsColumn.size);
    expect(settings.columns.find(FsColumn.attributes)?.visible, isTrue);
  });
}
