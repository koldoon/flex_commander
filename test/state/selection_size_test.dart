import 'package:flex_commander/model/settings/app_settings.dart';
import 'dart:async';

import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake/in_memory_tree_provider.dart';

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

/// Провайдер, обход которого останавливается посередине: сообщает частичную
/// сумму и ждёт, пока его не отпустят.
///
/// В памяти обход заканчивается быстрее, чем успевает пройти одна микрозадача,
/// и прерывание на середине иначе не воспроизвести.
class _HeldSizeProvider extends InMemoryTreeProvider {
  _HeldSizeProvider() : super(_entries());

  static const int partial = 120;

  final Completer<void> release = Completer<void>();

  @override
  AsyncOperation<int> calculateSize(List<FsNode> nodes) {
    return TaskOperation<int>((op) async {
      op.report(const OperationProgress(processed: partial));
      await release.future;
      op.checkCanceled();
      return 300;
    });
  }
}

/// Провайдер, у которого подсчёт размера не удаётся вовсе.
class _FailingSizeProvider extends InMemoryTreeProvider {
  _FailingSizeProvider() : super(_entries());

  @override
  AsyncOperation<int> calculateSize(List<FsNode> nodes) =>
      TaskOperation<int>((op) async => throw const FsError('/home/docs', FsErrorKind.permissionDenied));
}

/// Размер помеченного: файлы известны сразу, каталоги считаются фоном.
void main() {
  late InMemoryTreeProvider provider;
  late PanelController panel;

  setUp(() async {
    provider = InMemoryTreeProvider(_entries());
    panel = PanelController(provider: provider, settings: PanelSettings.defaults('/home'));
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

  /// Узел панели по имени: размеры каталогов живут в узлах, а не отдельно.
  DirectoryNode nodeNamed(String name, [PanelController? of]) =>
      (of ?? panel).nodes.whereType<DirectoryNode>().firstWhere((node) => node.name == name);

  /// Панель на своём провайдере — для тестов, которым нужен особый обход.
  Future<PanelController> panelOn(TreeProvider source) async {
    final it = PanelController(provider: source, settings: PanelSettings.defaults('/home'));
    addTearDown(it.dispose);
    await it.openPath('/home');
    return it;
  }

  test('размер файла виден сразу', () async {
    mark('notes.txt');

    expect(panel.selectionSize, 50);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('каталог добавляет в сумму своё содержимое', () async {
    mark('docs');
    expect(panel.selectionSizeIsFinal, isFalse);

    await settle();

    expect(panel.selectionSize, 300);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('файлы и каталоги складываются', () async {
    mark('docs');
    mark('notes.txt');

    await settle();

    expect(panel.selectionSize, 350);
  });

  test('известное показывается сразу, каталоги досчитываются потом', () async {
    final seen = <int>[];
    panel.addListener(() => seen.add(panel.selectionSize));

    mark('notes.txt');
    mark('docs');

    // Обход ещё не начинался, но размер файла уже виден: ждать подсчёта
    // каталога, чтобы показать хоть что-то, незачем.
    expect(panel.selectionSize, 50);
    expect(panel.selectionSizeIsFinal, isFalse);

    await settle();

    expect(panel.selectionSize, 350);
    expect(seen.last, 350);
  });

  test('снятие пометки прекращает подсчёт', () async {
    mark('docs');
    panel.selection.clear();

    await settle();

    expect(panel.selectionSize, 0);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('новый каталог встаёт в очередь, не прерывая начатое', () async {
    mark('docs');
    // Ещё не досчитали первый — помечаем второй.
    mark('bin');

    await settle();

    // Оба посчитаны: второй не отменил обход первого, а дождался очереди.
    expect(panel.selectionSize, 700);
    expect(panel.selectionSizeIsFinal, isTrue);
  });

  test('снятая пометка уходит из суммы и из очереди', () async {
    mark('docs');
    mark('bin');
    await settle();
    expect(panel.selectionSize, 700);

    panel.setCursorToName('bin');
    panel.toggleCurrentMark();
    await settle();

    expect(panel.selectionSize, 300);
  });

  test('новая пометка считается заново, а не поверх старой', () async {
    mark('docs');
    await settle();
    expect(panel.selectionSize, 300);

    panel.selection.clear();
    mark('bin');
    await settle();

    expect(panel.selectionSize, 400);
  });

  test('пока подсчёт идёт, сумма не выдаётся за окончательную', () async {
    mark('docs');

    // Обход ещё не закончился: показывать эту сумму как итог нельзя.
    expect(panel.selectionSizeIsFinal, isFalse);

    await settle();
    expect(panel.selectionSizeIsFinal, isTrue);
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

      panel.selection.clear();
      await settle();

      // В колонке размер остаётся: он всё ещё верен. В сумму не идёт — сумма
      // считает только помеченное.
      expect(nodeNamed('docs').size, 300);
      expect(panel.selectionSize, 0);
    });

    test('прерванный обход не оставляет частичного размера', () async {
      final held = _HeldSizeProvider();
      final panel = await panelOn(held);
      panel.setCursorToName('docs');
      panel.toggleCurrentMark();
      await Future<void>.delayed(Duration.zero);

      // Обход дошёл до середины и сообщил частичную сумму.
      expect(nodeNamed('docs', panel).size, _HeldSizeProvider.partial);

      panel.selection.clear();
      await settle();

      // Частичная сумма, застывшая как итог, была бы ложью.
      expect(nodeNamed('docs', panel).size, FsNode.unknownSize);
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
      expect(panel.selectionSizeIsFinal, isTrue);
    });

    test('повторная пометка посчитанного каталога обходится без обхода', () async {
      mark('docs');
      await settle();

      panel.selection.clear();
      mark('docs');

      // Синхронно, без ожидания: значение в узле авторитетно.
      expect(panel.selectionSizeIsFinal, isTrue);
      expect(panel.selectionSize, 300);
    });

    test('пустой каталог получает ноль, а не остаётся неизвестным', () async {
      mark('empty');
      await settle();

      expect(nodeNamed('empty').size, 0);

      // Ноль — это «посчитан», поэтому второй раз в очередь он не встаёт.
      mark('notes.txt');
      expect(panel.selectionSizeIsFinal, isTrue);
    });
  });

  group('перечитывание и уход', () {
    test('перечитывание во время обхода подсчёт не теряет', () async {
      mark('docs');
      // Не дожидаясь конца обхода: узлы сейчас заменятся новыми.
      await panel.reload();

      // Обход перезапущен на новых узлах, а не выброшен молча.
      expect(panel.selectionSizeIsFinal, isFalse);

      await settle();
      expect(panel.selectionSize, 300);
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
      expect(panel.selectionSize, 300);
    });

    test('уход в другой каталог обход отменяет', () async {
      mark('docs');
      await panel.openPath('/home/bin');
      await settle();

      expect(panel.selectionSize, 0);
      expect(panel.selectionSizeIsFinal, isTrue);
    });
  });
}
