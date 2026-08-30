import 'dart:async';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

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
    panel = testPanel(provider: provider, settings: PanelSettings.defaults('/home'));
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
      // Каталоги пока не в счёт: их размер считается фоном, а проверка идёт
      // синхронно, до первого шага подсчёта. Появится рядом `await` — числа
      // поедут, и это будет не поломка, а досчитанные каталоги.
      expect(panel.selection.totalSize, 2148); // 100 + 2048
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
      provider.removeEntry('/home/report.xlsx');

      await panel.reload();

      expect(panel.currentNode?.name, isNot('report.xlsx'));
      expect(panel.cursorIndex, lessThanOrEqualTo(index));
    });

    test('исчезнувшие помеченные объекты отбрасываются', () async {
      panel.markAll();
      provider.removeEntry('/home/notes.txt');

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

  group('курсор между запусками', () {
    test('положение курсора попадает в настройки', () async {
      await panel.openPath('/home');
      panel.setCursorToName('report.xlsx');

      expect(panel.settings.cursor, 'report.xlsx');
    });

    test('прочитанное из настроек ставит курсор при открытии', () async {
      final restored = testPanel(provider: provider, settings: PanelSettings(path: '/home', cursor: 'report.xlsx'));
      addTearDown(restored.dispose);

      await restored.openPath('/home');

      expect(restored.currentNode?.name, 'report.xlsx');
    });

    test('исчезнувший объект ставит курсор в начало, а не мимо', () async {
      final restored = testPanel(
        provider: provider,
        settings: PanelSettings(path: '/home', cursor: 'его-больше-нет.txt'),
      );
      addTearDown(restored.dispose);

      await restored.openPath('/home');

      expect(restored.cursorIndex, 0);
      expect(restored.currentNode, isNotNull);
    });

    test('запомненное не теряется, пока каталог не прочитан', () {
      // Настройки могут сохраниться и до первого чтения — например, если
      // приложение закрыли сразу после запуска.
      final restored = testPanel(provider: provider, settings: PanelSettings(path: '/home', cursor: 'report.xlsx'));
      addTearDown(restored.dispose);

      expect(restored.settings.cursor, 'report.xlsx');
    });

    test('курсор помнится для каждого каталога свой', () async {
      await panel.openPath('/home');
      panel.setCursorToName('report.xlsx');

      await panel.openPath('/home/docs');
      expect(panel.settings.cursor, isNot('report.xlsx'));

      await panel.openPath('/home');
      expect(panel.currentNode?.name, 'report.xlsx');
    });
  });

  group('работа от имени панели', () {
    /// Работа, которой можно управлять из теста: держится, пока её не отпустят.
    (TaskOperation<String, String>, Completer<String>) held() {
      final gate = Completer<String>();
      final operation = TaskOperation<String, String>((op, params) async {
        op.report(message: 'Reading $params…');
        final value = await gate.future;
        op.checkCanceled();
        return value;
      });
      return (operation, gate);
    }

    test('пока работа идёт, панель занята и говорит о ней', () async {
      await panel.openPath('/home');
      final (operation, gate) = held();

      final work = panel.runWork(operation, 'notes.txt', status: 'Loading…');
      await pumpEventQueue(times: 1);

      expect(panel.busy, isTrue);
      expect(panel.statusText, 'Reading notes.txt…', reason: 'веха работы вытеснила начальное слово');
      // Список файлов на виду: читается один файл, а не каталог.
      expect(panel.nodes, isNotEmpty);

      gate.complete('готово');
      expect(await work, 'готово');
      expect(panel.busy, isFalse);
      expect(panel.statusText, isNull);
    });

    test('до первой вехи видно то, что сказал заказчик', () async {
      await panel.openPath('/home');
      final operation = TaskOperation<String, String>((op, params) async => params);

      final work = panel.runWork(operation, 'x', status: 'Reading…');
      expect(panel.statusText, 'Reading…');

      await work;
    });

    test('отмена приходит OperationCanceled и освобождает панель', () async {
      await panel.openPath('/home');
      final (operation, gate) = held();

      final work = panel.runWork(operation, 'notes.txt');
      // Ожидание вешается заранее: `cancel` отклоняет работу немедленно, и
      // отказ без слушателя ушёл бы в необработанные.
      final canceled = expectLater(work, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      panel.cancel();
      gate.complete('поздно');
      await canceled;

      expect(panel.busy, isFalse);
      expect(panel.statusText, isNull);
      expect(panel.currentNode, isNotNull, reason: 'панель осталась там же, где была');
    });

    test('отказ работы тоже снимает занятость', () async {
      await panel.openPath('/home');
      final operation = TaskOperation<String, String>((op, params) async {
        throw const FsError('/home/notes.txt', FsErrorKind.permissionDenied);
      });

      final work = panel.runWork(operation, 'x');
      await expectLater(work, throwsA(isA<FsError>()));

      expect(panel.busy, isFalse);
      // Ошибку в строке не оставляем: о неудаче говорит заказчик.
      expect(panel.statusText, isNull);
    });

    test('вторая работа отменяет первую, а занятость остаётся её', () async {
      await panel.openPath('/home');
      final (first, firstGate) = held();
      final (second, secondGate) = held();

      final firstWork = panel.runWork(first, 'первый');
      final firstCanceled = expectLater(firstWork, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      final secondWork = panel.runWork(second, 'второй');
      await pumpEventQueue(times: 1);

      firstGate.complete('не нужен');
      await firstCanceled;
      // Первая ушла, но занятость теперь второй, и снимать её первой нельзя.
      expect(panel.busy, isTrue);
      expect(panel.statusText, 'Reading второй…');

      secondGate.complete('готово');
      expect(await secondWork, 'готово');
      expect(panel.busy, isFalse);
    });

    test('чтение каталога отменяет чужую работу', () async {
      await panel.openPath('/home');
      final (operation, gate) = held();

      final work = panel.runWork(operation, 'notes.txt');
      final canceled = expectLater(work, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      await panel.openPath('/home/docs');
      gate.complete('поздно');
      await canceled;

      expect(panel.busy, isFalse);
      expect(panel.directory?.pathString, '/home/docs');
    });
  });
}
