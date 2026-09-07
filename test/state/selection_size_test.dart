import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

List<FakeEntry> _entries() => [
  FakeEntry.directory('/home'),
  FakeEntry.directory('/home/docs'),
  FakeEntry.file('/home/docs/a.txt', size: 100),
  FakeEntry.directory('/home/docs/nested'),
  FakeEntry.file('/home/docs/nested/b.txt', size: 200),
  FakeEntry.directory('/home/bin'),
  FakeEntry.file('/home/bin/tool', size: 400),
  FakeEntry.directory('/home/empty'),
  FakeEntry.file('/home/notes.txt', size: 50),
];

/// Провайдер, обход которого останавливается посередине: содержимое верхнего
/// каталога он отдаёт, а во вложенный не пускает, пока его не отпустят.
///
/// В памяти обход заканчивается быстрее, чем успевает пройти одна микрозадача,
/// и прерывание на середине иначе не воспроизвести.
class _HeldSizeProvider extends InMemoryTreeProvider {
  // Двух файлов достаточно, чтобы одна сумма ушла сразу, а вторая осталась
  // ждать своей очереди у ограничителя перерисовки — там её и застаёт смена
  // списка.
  _HeldSizeProvider() : super([..._entries(), FakeEntry.file('/home/docs/b.bin', size: 7)]);

  /// Что успело насчитаться до остановки: `a.txt` и `b.bin`.
  static const int partial = 107;

  final Completer<void> release = Completer<void>();

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    final children = await super.listChildren(dir);
    if (dir.name == 'nested') {
      await release.future;
    }
    return children;
  }
}

/// Провайдер, который считает, сколько обходов идёт одновременно.
///
/// Каждый обход останавливается на первом же каталоге и ждёт, пока его не
/// отпустят, поэтому предел пула виден напрямую.
class _CountingSizeProvider extends InMemoryTreeProvider {
  _CountingSizeProvider() : super(_entries());

  final Completer<void> release = Completer<void>();

  int running = 0;
  int peak = 0;

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async {
    running++;
    peak = running > peak ? running : peak;
    await release.future;
    running--;
    return super.listChildren(dir);
  }
}

/// Провайдер, у которого каталог не читается вовсе.
class _FailingSizeProvider extends InMemoryTreeProvider {
  _FailingSizeProvider() : super(_entries());

  @override
  Future<List<FsNode>> listChildren(DirectoryNode dir) async =>
      throw const FsError('/home/docs', FsErrorKind.permissionDenied);
}

/// Размер помеченного: файлы известны сразу, каталоги считаются фоном.
void main() {
  late InMemoryTreeProvider provider;
  late TestPanel panel;

  setUp(() async {
    provider = InMemoryTreeProvider(_entries());
    panel = testPanel(provider: provider, settings: PanelSettings.defaults('/home'));
    await panel.openPath('/home');
  });

  tearDown(() => panel.dispose());

  /// Даёт фоновому подсчёту дойти до конца.
  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void mark(String name) {
    panel.setCursorToName(name);
    panel.toggleCurrentMark();
  }

  /// Что показывает строка списка. Растущая сумма в узел не пишется — её
  /// подставляют при чтении, — поэтому спрашивать надо там же, где спрашивает
  /// экран.
  int shownSize(String name, [TestPanel? of]) =>
      (of ?? panel).session.entries.firstWhere((entry) => entry.name == name).size;

  /// Узел панели по имени: посчитанные размеры каталогов живут в узлах.
  DirectoryNode nodeNamed(String name, [TestPanel? of]) =>
      (of ?? panel).session.nodes.whereType<DirectoryNode>().firstWhere((node) => node.name == name);

  /// Панель на своём провайдере — для тестов, которым нужен особый обход.
  Future<TestPanel> panelOn(TreeProvider source, {int concurrency = 1}) async {
    final it = testPanel(provider: source, settings: PanelSettings.defaults('/home'), sizeScanConcurrency: concurrency);
    addTearDown(it.dispose);
    await it.openPath('/home');
    return it;
  }

  test('размер файла виден сразу', () async {
    mark('notes.txt');

    expect(panel.markedSize, 50);
    expect(panel.markedSizeIsFinal, isTrue);
  });

  test('каталог добавляет в сумму своё содержимое', () async {
    mark('docs');
    expect(panel.markedSizeIsFinal, isFalse);

    await settle();

    expect(panel.markedSize, 300);
    expect(panel.markedSizeIsFinal, isTrue);
  });

  test('файлы и каталоги складываются', () async {
    mark('docs');
    mark('notes.txt');

    await settle();

    expect(panel.markedSize, 350);
  });

  test('известное показывается сразу, каталоги досчитываются потом', () async {
    final seen = <int>[];
    panel.addListener(() => seen.add(panel.markedSize));

    mark('notes.txt');
    mark('docs');

    // Обход ещё не начинался, но размер файла уже виден: ждать подсчёта
    // каталога, чтобы показать хоть что-то, незачем.
    expect(panel.markedSize, 50);
    expect(panel.markedSizeIsFinal, isFalse);

    await settle();

    expect(panel.markedSize, 350);
    expect(seen.last, 350);
  });

  test('снятие пометки прекращает подсчёт', () async {
    mark('docs');
    panel.clearMarks();

    await settle();

    expect(panel.markedSize, 0);
    expect(panel.markedSizeIsFinal, isTrue);
  });

  test('новый каталог встаёт в очередь, не прерывая начатое', () async {
    mark('docs');
    // Ещё не досчитали первый — помечаем второй.
    mark('bin');

    await settle();

    // Оба посчитаны: второй не отменил обход первого, а дождался очереди.
    expect(panel.markedSize, 700);
    expect(panel.markedSizeIsFinal, isTrue);
  });

  test('снятая пометка уходит из суммы и из очереди', () async {
    mark('docs');
    mark('bin');
    await settle();
    expect(panel.markedSize, 700);

    panel.setCursorToName('bin');
    panel.toggleCurrentMark();
    await settle();

    expect(panel.markedSize, 300);
  });

  test('новая пометка считается заново, а не поверх старой', () async {
    mark('docs');
    await settle();
    expect(panel.markedSize, 300);

    panel.clearMarks();
    mark('bin');
    await settle();

    expect(panel.markedSize, 400);
  });

  test('пока подсчёт идёт, сумма не выдаётся за окончательную', () async {
    mark('docs');

    // Обход ещё не закончился: показывать эту сумму как итог нельзя.
    expect(panel.markedSizeIsFinal, isFalse);

    await settle();
    expect(panel.markedSizeIsFinal, isTrue);
  });

  group('размер в узле', () {
    test('посчитанное оказывается в самом узле', () async {
      mark('docs');
      await settle();

      // Отсюда его берёт колонка «Size» в таблице.
      expect(nodeNamed('docs').size, 300);
    });

    test('промежуточная сумма попадает в узел до конца обхода', () async {
      mark('docs');

      final seen = <int>[];
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(Duration.zero);
        seen.add(nodeNamed('docs').size);
      }

      // Размер стал известен раньше, чем обход закончился, и только рос.
      final known = seen.where((size) => size != FsNode.unknownSize).toList();
      expect(known, isNotEmpty);
      expect(known, orderedEquals(List.of(known)..sort()));
      expect(known.last, 300);
    });

    test('снятие пометки посчитанное не стирает', () async {
      mark('docs');
      await settle();

      panel.clearMarks();
      await settle();

      // В колонке размер остаётся: он всё ещё верен. В сумму не идёт — сумма
      // считает только помеченное.
      expect(nodeNamed('docs').size, 300);
      expect(panel.markedSize, 0);
    });

    test('прерванный обход не оставляет частичного размера', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      // Столько, чтобы обход успел дойти до вложенного каталога и встать.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Обход дошёл до середины и сообщил частичную сумму.
      expect(shownSize('docs', panel), _HeldSizeProvider.partial);
      // В узле её при этом нет: узел хранит только известное окончательно.
      expect(nodeNamed('docs', panel).size, FsNode.unknownSize);

      panel.clearMarks();
      await settle();

      // Частичная сумма, застывшая как итог, была бы ложью.
      expect(shownSize('docs', panel), FsNode.unknownSize);
      held.release.complete();
    });

    test('недоступный каталог не встаёт в очередь снова', () async {
      final panel = await panelOn(_FailingSizeProvider());
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      await settle();

      // Ноль, а не «не посчитан»: иначе каталог обходился бы заново на каждое
      // нажатие.
      expect(nodeNamed('docs', panel).size, 0);

      panel.setCursorToName('notes.txt');
      panel.toggleCurrentMark();
      expect(panel.markedSizeIsFinal, isTrue);
    });

    test('повторная пометка посчитанного каталога обходится без обхода', () async {
      mark('docs');
      await settle();

      panel.clearMarks();
      mark('docs');

      // Синхронно, без ожидания: значение в узле авторитетно.
      expect(panel.markedSizeIsFinal, isTrue);
      expect(panel.markedSize, 300);
    });

    test('пустой каталог получает ноль, а не остаётся неизвестным', () async {
      mark('empty');
      await settle();

      expect(nodeNamed('empty').size, 0);

      // Ноль — это «посчитан», поэтому второй раз в очередь он не встаёт.
      mark('notes.txt');
      expect(panel.markedSizeIsFinal, isTrue);
    });
  });

  group('пул обхода', () {
    /// Даёт обходам стартовать, но не завершиться.
    Future<void> start() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('несколько каталогов считаются одновременно', () async {
      final counting = _CountingSizeProvider();
      final panel = await panelOn(counting, concurrency: 10);

      for (final name in ['docs', 'bin', 'empty']) {
        panel.setCursorToName(name);
        panel.toggleCurrentMark();
      }
      await start();

      // Все три сразу: по очереди пришлось бы ждать самый медленный каталог.
      expect(counting.peak, 3);
      counting.release.complete();
    });

    test('размер пула ограничивает число одновременных обходов', () async {
      final counting = _CountingSizeProvider();
      final panel = await panelOn(counting, concurrency: 2);

      for (final name in ['docs', 'bin', 'empty']) {
        panel.setCursorToName(name);
        panel.toggleCurrentMark();
      }
      await start();

      // Третий ждёт в очереди: сотня одновременных обходов завалила бы диск.
      expect(counting.peak, 2);
      expect(panel.markedSizeIsFinal, isFalse);
      counting.release.complete();
    });

    test('провайдер вправе сузить пул: настройка — это пожелание, а не приказ', () async {
      final counting = _CountingSizeProvider()..capabilities = const ProviderCapabilities(maxConcurrency: 1);
      // Пользователь просит десять, провайдер выдерживает одну.
      final panel = await panelOn(counting, concurrency: 10);

      for (final name in ['docs', 'bin', 'empty']) {
        panel.setCursorToName(name);
        panel.toggleCurrentMark();
      }
      await start();

      expect(counting.peak, 1);
      counting.release.complete();
    });

    test('освободившееся место в пуле занимает следующий из очереди', () async {
      final panel = await panelOn(InMemoryTreeProvider(_entries()), concurrency: 1);

      for (final name in ['docs', 'bin']) {
        panel.setCursorToName(name);
        panel.toggleCurrentMark();
      }
      await settle();

      // Пул из одного — это прежняя последовательная очередь, и она доходит
      // до конца.
      expect(panel.markedSize, 700);
      expect(panel.markedSizeIsFinal, isTrue);
    });
  });

  group('посчитанное живёт по путям', () {
    test('тихое чтение за курсором дерева посчитанного не теряет', () async {
      mark('docs');
      await settle();
      expect(nodeNamed('docs').size, 300);

      // Так дерево водит панель за курсором: каталог меняется тихо, а узлы
      // при этом заменяются новыми.
      await panel.session.follow('/home/bin');
      await panel.session.follow('/home');
      await settle();

      // Размер на месте, и обход заново не начинался — иначе число мигало бы
      // прочерком на каждом шаге курсора по дереву.
      expect(nodeNamed('docs').size, 300);
      expect(panel.markedSizeIsFinal, isTrue);
    });

    test('растущая сумма видна и снаружи, пока обход идёт', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Так спрашивает дерево: помеченная ветвь бывает не в списке панели, и
      // без этого она молчала бы прочерком до конца обхода.
      expect(panel.session.measuredSizes(['/home/docs']), {'/home/docs': _HeldSizeProvider.partial});

      panel.clearMarks();
      await settle();

      // Обход оборвался — число уходит вместе с ним.
      expect(panel.session.measuredSizes(['/home/docs']), isEmpty);
      held.release.complete();
    });

    test('размер не приезжает на строку чужого списка', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Дерево уводит панель внутрь помеченного каталога: строки сменились, а
      // частичная сумма записана номером строки прежнего списка.
      await panel.session.follow('/home/docs');
      held.release.complete();
      await settle();

      // Число помеченного каталога, приписанное чужой строке, — то самое, что
      // было видно живьём: у соседней ветви появлялся размер родителя.
      for (final entry in panel.entries) {
        expect(entry.size, isNot(_HeldSizeProvider.partial), reason: 'у ${entry.name} чужое число');
      }
    });

    test('перечитывание не гасит растущую сумму', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Дерево водит панель по ветвям: ушли и вернулись, узлы новые.
      await panel.session.follow('/home/bin');
      await panel.session.follow('/home');

      // Число на месте сразу, а не через сообщение обхода: их придерживает
      // ограничитель перерисовки, и всё это время строка стояла бы пустой.
      expect(shownSize('docs', panel), _HeldSizeProvider.partial);
      held.release.complete();
      await settle();
    });

    test('прерванный обход не оставляет числа и в свежих узлах', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Дерево водило панель по ветвям: узел в списке уже не тот, с которого
      // начинался обход, но растущую сумму он получил.
      await panel.session.follow('/home/bin');
      await panel.session.follow('/home');
      expect(shownSize('docs', panel), _HeldSizeProvider.partial);

      // Esc: пометка снята, обход прекращён.
      panel.clearMarks();
      await settle();

      // Ни в строке, ни в узле, ни в ответах — иначе число вернётся с
      // ближайшим списком.
      expect(shownSize('docs', panel), FsNode.unknownSize);
      expect(nodeNamed('docs', panel).size, FsNode.unknownSize);
      expect(panel.session.measuredSizes(['/home/docs']), isEmpty);
      held.release.complete();
    });

    test('снятие пометки убирает растущую сумму и со строки, и с той стороны', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(shownSize('docs', panel), _HeldSizeProvider.partial);

      // Тем же Space по тому же каталогу: пометка снята, обход прекращён.
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      await settle();

      expect(shownSize('docs', panel), FsNode.unknownSize);
      // И та сторона узнала: отмена обязана разбудить границу сама — обход,
      // который её будил, уже мёртв.
      expect(panel.entries.firstWhere((entry) => entry.name == 'docs').size, FsNode.unknownSize);
      held.release.complete();
    });

    test('остановленный подсчёт убирает число и со строки той стороны', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      // Ограничитель перерисовки держит числа до 50 мс: без настоящего
      // ожидания сообщение о размере не уедет вовсе.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(
        panel.entries.firstWhere((entry) => entry.name == 'docs').size,
        _HeldSizeProvider.partial,
        reason: 'растущая сумма видна',
      );

      panel.clearMarks();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();

      // Остановили — числа нет: половина, застывшая в колонке, хуже прочерка.
      expect(panel.entries.firstWhere((entry) => entry.name == 'docs').size, FsNode.unknownSize);
      held.release.complete();
    });

    test('размеры подкаталогов остаются от того же обхода', () async {
      mark('docs');
      await settle();

      await panel.openPath('/home/docs');

      // Обход и так проходил через `nested` — сумма просто перестала
      // выбрасываться.
      expect(nodeNamed('nested').size, 200);
    });
  });

  group('перечитывание и уход', () {
    test('перечитывание во время обхода подсчёт не теряет', () async {
      mark('docs');
      // Не дожидаясь конца обхода: узлы сейчас заменятся новыми.
      await panel.reload();

      // Обход перезапущен на новых узлах, а не выброшен молча.
      expect(panel.markedSizeIsFinal, isFalse);

      await settle();
      expect(panel.markedSize, 300);
      expect(nodeNamed('docs').size, 300);
    });

    test('перечитывание сбрасывает посчитанный размер', () async {
      mark('docs');
      await settle();
      final before = nodeNamed('docs');

      await panel.reload();

      // Узлы новые, и размер считается заново: содержимое могло измениться.
      expect(nodeNamed('docs'), isNot(same(before)));
      await settle();
      expect(nodeNamed('docs').size, 300);
    });

    test('неудачное перечитывание обход не прерывает', () async {
      mark('docs');
      provider.denied['/home'] = const FsError('/home', FsErrorKind.permissionDenied);

      await panel.reload();
      await settle();

      // На экране остались прежние узлы, и обход над ними правомерен.
      expect(panel.markedSize, 300);
    });

    test('уход в другой каталог обход отменяет', () async {
      mark('docs');
      await panel.openPath('/home/bin');
      await settle();

      expect(panel.markedSize, 0);
      expect(panel.markedSizeIsFinal, isTrue);
    });
  });
}
