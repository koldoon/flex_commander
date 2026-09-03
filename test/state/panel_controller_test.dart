import 'dart:async';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTreeProvider provider;
  late TestPanel panel;

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

  List<String> namesOf(Panel panel) => panel.entries.map((n) => n.name).toList();

  group('открытие каталога', () {
    test('читает содержимое и сортирует его', () async {
      expect(await panel.openPath('/home'), isTrue);

      expect(panel.phase, PanelPhase.idle);
      expect(panel.session.path, '/home');
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
      expect(panel.session.directory, isNull);
    });

    test('путь к файлу не открывается', () async {
      expect(await panel.openPath('/home/notes.txt'), isFalse);
    });

    test('ошибка чтения оставляет панель в прежнем каталоге', () async {
      await panel.openPath('/home');
      provider.denied['/home/docs'] = const FsError('/home/docs', FsErrorKind.permissionDenied);

      final docs = panel.session.nodes.firstWhere((n) => n.name == 'docs') as DirectoryNode;
      await panel.session.open(docs);

      expect(panel.phase, PanelPhase.error);
      expect(panel.error?.kind, FsErrorKind.permissionDenied);
      expect(panel.session.path, '/home');
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
      final docs = panel.session.nodes.firstWhere((n) => n.name == 'docs') as DirectoryNode;
      final bin = panel.session.nodes.firstWhere((n) => n.name == 'bin') as DirectoryNode;

      final first = panel.session.open(docs);
      final second = panel.session.open(bin);
      await Future.wait([first, second]);

      expect(panel.session.path, '/home/bin');
      expect(panel.busy, isFalse);
    });
  });

  group('навигация', () {
    setUp(() => panel.openPath('/home'));

    test('вход в каталог под курсором', () async {
      panel.setCursorToName('docs');
      expect(await panel.enterCurrent(), isNull);

      expect(panel.session.path, '/home/docs');
      expect(namesOf(panel), ['..', 'readme.md']);
    });

    test('вход в ссылку показывает путь через саму ссылку', () async {
      panel.setCursorToName('link-to-bin');
      expect(await panel.enterCurrent(), isNull);

      // Содержимое берётся из цели, но пользователь пришёл через ссылку —
      // её и должен видеть в заголовке панели.
      expect(panel.session.path, '/home/link-to-bin');
    });

    test('из каталога, открытого по ссылке, наверх ведёт к самой ссылке', () async {
      panel.setCursorToName('link-to-bin');
      await panel.enterCurrent();

      await panel.goUp();

      // Не в /home/bin/.. и не в физического родителя цели, а туда,
      // откуда пользователь пришёл.
      expect(panel.session.path, '/home');
      expect(panel.currentEntry?.name, 'link-to-bin');
    });

    test('".." внутри ссылки работает так же, как переход наверх', () async {
      panel.setCursorToName('link-to-bin');
      await panel.enterCurrent();

      panel.setCursorToFirst();
      expect(panel.currentEntry?.isParent, isTrue);
      await panel.enterCurrent();

      expect(panel.session.path, '/home');
      expect(panel.currentEntry?.name, 'link-to-bin');
    });

    test('путь через ссылку восстанавливается из настроек', () async {
      expect(await panel.openPath('/home/link-to-bin'), isTrue);

      expect(panel.session.path, '/home/link-to-bin');
      expect(panel.session.settings.path, '/home/link-to-bin');
    });

    test('файл возвращается вызывающему коду', () async {
      panel.setCursorToName('notes.txt');
      final node = await panel.enterCurrent();

      expect(node?.name, 'notes.txt');
      expect(panel.session.path, '/home');
    });

    test('".." поднимает на уровень вверх', () async {
      await panel.openPath('/home/docs');
      panel.setCursorIndex(0);
      expect(panel.currentEntry?.isParent, isTrue);

      await panel.enterCurrent();
      expect(panel.session.path, '/home');
    });

    test('после подъёма курсор стоит на покинутом каталоге', () async {
      panel.setCursorToName('docs');
      await panel.enterCurrent();
      await panel.goUp();

      expect(panel.currentEntry?.name, 'docs');
    });

    test('в корне подниматься некуда', () async {
      await panel.openPath('/');
      await panel.goUp();

      expect(panel.session.path, '/');
    });

    test('возврат в посещённый каталог восстанавливает курсор', () async {
      panel.setCursorToName('report.xlsx');
      await panel.openPath('/home/docs');
      await panel.openPath('/home');

      expect(panel.currentEntry?.name, 'report.xlsx');
    });

    test('подъём наверх важнее запомненного курсора', () async {
      // Курсор был на файле, но пользователь ушёл в каталог и вернулся "вверх":
      // ожидание в таком случае — курсор на покинутом каталоге.
      panel.setCursorToName('report.xlsx');
      final docs = panel.session.nodes.firstWhere((n) => n.name == 'docs') as DirectoryNode;

      await panel.session.open(docs);
      await panel.goUp();

      expect(panel.currentEntry?.name, 'docs');
    });
  });

  group('курсор', () {
    setUp(() => panel.openPath('/home'));

    test('движение ограничено границами списка', () {
      panel.moveCursor(-5);
      expect(panel.cursorIndex, 0);

      panel.moveCursor(100);
      expect(panel.cursorIndex, panel.entries.length - 1);
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
      expect(panel.currentEntry?.name, 'report.xlsx');

      panel.setCursorToFirst();
      expect(panel.currentEntry?.name, '..');
    });

    test('несуществующее имя не двигает курсор', () {
      panel.setCursorToName('docs');
      panel.setCursorToName('нет такого файла');
      expect(panel.currentEntry?.name, 'docs');
    });
  });

  group('пометка', () {
    setUp(() => panel.openPath('/home'));

    test('пометка сдвигает курсор вниз', () {
      panel.setCursorToName('notes.txt');
      panel.toggleCurrentMark();

      expect(panel.marked, {'notes.txt'});
      expect(panel.currentEntry?.name, 'report.xlsx');
    });

    test('".." не помечается', () {
      panel.setCursorToFirst();
      panel.toggleCurrentMark();

      expect(panel.marked.isEmpty, isTrue);
    });

    test('суммарный размер считает только известные размеры', () {
      panel.markAll();

      expect(panel.marked.length, panel.entries.length - 1); // без ".."
      // Каталоги пока не в счёт: их размер считается фоном, а проверка идёт
      // синхронно, до первого шага подсчёта. Появится рядом `await` — числа
      // поедут, и это будет не поломка, а досчитанные каталоги.
      expect(panel.session.selection.totalSize, 2148); // 100 + 2048
    });

    test('открытие другого каталога снимает пометку', () async {
      panel.markAll();
      await panel.openPath('/home/docs');

      expect(panel.marked.isEmpty, isTrue);
    });
  });

  group('перечитывание', () {
    setUp(() => panel.openPath('/home'));

    test('сохраняет курсор и пометку по именам', () async {
      panel.setCursorToName('notes.txt');
      panel.session.selection.add(panel.session.nodes.firstWhere((n) => n.name == 'report.xlsx'));

      await panel.reload();

      expect(panel.currentEntry?.name, 'notes.txt');
      expect(panel.marked, {'report.xlsx'});
      // Узлы после перечитывания — новые экземпляры.
      expect(panel.session.selection.nodes.first, same(panel.session.nodes.firstWhere((n) => n.name == 'report.xlsx')));
    });

    test('исчезнувший объект под курсором заменяется соседним', () async {
      panel.setCursorToName('report.xlsx');
      final index = panel.cursorIndex;
      provider.removeEntry('/home/report.xlsx');

      await panel.reload();

      expect(panel.currentEntry?.name, isNot('report.xlsx'));
      expect(panel.cursorIndex, lessThanOrEqualTo(index));
    });

    test('исчезнувшие помеченные объекты отбрасываются', () async {
      panel.markAll();
      provider.removeEntry('/home/notes.txt');

      await panel.reload();

      expect(panel.marked, isNot(contains('notes.txt')));
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

      expect(panel.currentEntry?.name, 'notes.txt');
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

    final settings = panel.session.settings;
    expect(settings.path, '/home/docs');
    expect(settings.sort.column, FsColumn.size);
    expect(settings.columns.find(FsColumn.attributes)?.visible, isTrue);
  });

  group('курсор между запусками', () {
    test('положение курсора попадает в настройки', () async {
      await panel.openPath('/home');
      panel.setCursorToName('report.xlsx');

      expect(panel.session.settings.cursor, 'report.xlsx');
    });

    test('прочитанное из настроек ставит курсор при открытии', () async {
      final restored = testPanel(provider: provider, settings: PanelSettings(path: '/home', cursor: 'report.xlsx'));
      addTearDown(restored.dispose);

      await restored.openPath('/home');

      expect(restored.session.currentNode?.name, 'report.xlsx');
    });

    test('исчезнувший объект ставит курсор в начало, а не мимо', () async {
      final restored = testPanel(
        provider: provider,
        settings: PanelSettings(path: '/home', cursor: 'его-больше-нет.txt'),
      );
      addTearDown(restored.dispose);

      await restored.openPath('/home');

      expect(restored.cursorIndex, 0);
      expect(restored.session.currentNode, isNotNull);
    });

    test('запомненное не теряется, пока каталог не прочитан', () {
      // Настройки могут сохраниться и до первого чтения — например, если
      // приложение закрыли сразу после запуска.
      final restored = testPanel(provider: provider, settings: PanelSettings(path: '/home', cursor: 'report.xlsx'));
      addTearDown(restored.dispose);

      expect(restored.session.settings.cursor, 'report.xlsx');
    });

    test('курсор помнится для каждого каталога свой', () async {
      await panel.openPath('/home');
      panel.setCursorToName('report.xlsx');

      await panel.openPath('/home/docs');
      expect(panel.session.settings.cursor, isNot('report.xlsx'));

      await panel.openPath('/home');
      expect(panel.currentEntry?.name, 'report.xlsx');
    });
  });

  group('работа от имени панели', () {
    /// Тело, которым можно управлять из теста: держится, пока не отпустят.
    ///
    /// Возвращает и саму заслонку, и тело: одно без другого тесту бесполезно.
    (Future<String> Function(TaskOperation<void, String>), Completer<String>) held(String name) {
      final gate = Completer<String>();
      Future<String> body(TaskOperation<void, String> op) async {
        op.report(message: 'Reading $name…');
        final value = await gate.future;
        op.checkCanceled();
        return value;
      }

      return (body, gate);
    }

    test('пока работа идёт, панель занята и говорит о ней', () async {
      await panel.openPath('/home');
      final (body, gate) = held('notes.txt');

      final work = panel.runWork(body, status: 'Loading…');
      await pumpEventQueue(times: 1);

      expect(panel.busy, isTrue);
      expect(panel.statusText, 'Reading notes.txt…', reason: 'веха работы вытеснила начальное слово');
      // Список файлов на виду: читается один файл, а не каталог.
      expect(panel.entries, isNotEmpty);

      gate.complete('готово');
      expect(await work, 'готово');
      expect(panel.busy, isFalse);
      expect(panel.statusText, isNull);
    });

    test('до первой вехи видно то, что сказал заказчик', () async {
      await panel.openPath('/home');
      final work = panel.runWork((op) async => 'x', status: 'Reading…');
      expect(panel.statusText, 'Reading…');

      await work;
    });

    test('отмена приходит OperationCanceled и освобождает панель', () async {
      await panel.openPath('/home');
      final (body, gate) = held('notes.txt');

      final work = panel.runWork(body);
      // Ожидание вешается заранее: `cancel` отклоняет работу немедленно, и
      // отказ без слушателя ушёл бы в необработанные.
      final canceled = expectLater(work, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      panel.cancel();
      gate.complete('поздно');
      await canceled;

      expect(panel.busy, isFalse);
      expect(panel.statusText, isNull);
      expect(panel.currentEntry, isNotNull, reason: 'панель осталась там же, где была');
    });

    test('отказ работы тоже снимает занятость', () async {
      await panel.openPath('/home');
      final work = panel.runWork<String>((op) async {
        throw const FsError('/home/notes.txt', FsErrorKind.permissionDenied);
      });
      await expectLater(work, throwsA(isA<FsError>()));

      expect(panel.busy, isFalse);
      // Ошибку в строке не оставляем: о неудаче говорит заказчик.
      expect(panel.statusText, isNull);
    });

    test('вторая работа отменяет первую, а занятость остаётся её', () async {
      await panel.openPath('/home');
      final (first, firstGate) = held('первый');
      final (second, secondGate) = held('второй');

      final firstWork = panel.runWork(first);
      final firstCanceled = expectLater(firstWork, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      final secondWork = panel.runWork(second);
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

    test('цепочка — одна занятость: между звеньями панель не освобождается', () async {
      // Ради этого тело и принимается вместо готовой работы: шагов у дела
      // бывает несколько, а занятость и цель для `Esc` должны быть одни.
      await panel.openPath('/home');
      final first = Completer<String>();
      final second = Completer<String>();

      // Все значения занятости по ходу дела: провала в `false` быть не должно.
      final seen = <bool>[];
      void watch() => seen.add(panel.busy);
      panel.addListener(watch);
      addTearDown(() => panel.removeListener(watch));

      final work = panel.runWork<String>((op) async {
        await op.delegate(TaskOperation<void, String>((_, _) => first.future), null);
        return op.delegate(TaskOperation<void, String>((_, _) => second.future), null);
      });

      await pumpEventQueue(times: 1);
      first.complete('звено');
      await pumpEventQueue(times: 1);

      expect(panel.busy, isTrue, reason: 'первое звено кончилось, дело — нет');
      second.complete('готово');
      expect(await work, 'готово');

      expect(panel.busy, isFalse);
      expect(seen.sublist(0, seen.length - 1), everyElement(isTrue), reason: 'освободилась только в конце');
    });

    test('отмена доходит до вложенного звена', () async {
      await panel.openPath('/home');
      final inner = Completer<String>();
      var innerFinished = false;

      final work = panel.runWork<String>((op) async {
        return op.delegate(
          TaskOperation<void, String>((child, _) async {
            final value = await inner.future;
            // Проверка отмены — то самое место, где вложенная узнаёт о ней.
            child.checkCanceled();
            innerFinished = true;
            return value;
          }),
          null,
        );
      });
      final canceled = expectLater(work, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      // Прерывают снаружи, а работает самая вложенная — отмена идёт встречно.
      panel.cancel();
      inner.complete('поздно');
      await canceled;

      expect(innerFinished, isFalse, reason: 'вложенная встала на проверке отмены, а не дошла до конца');
      expect(panel.busy, isFalse);
    });

    test('чтение каталога отменяет чужую работу', () async {
      await panel.openPath('/home');
      final (body, gate) = held('notes.txt');

      final work = panel.runWork(body);
      final canceled = expectLater(work, throwsA(isA<OperationCanceled>()));
      await pumpEventQueue(times: 1);

      await panel.openPath('/home/docs');
      gate.complete('поздно');
      await canceled;

      expect(panel.busy, isFalse);
      expect(panel.session.path, '/home/docs');
    });
  });
}
