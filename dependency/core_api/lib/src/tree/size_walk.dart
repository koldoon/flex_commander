import 'dart:async';

import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';

/// Событие обхода поддерева.
///
/// Обход **ничего не решает за того, кто его читает**: он отдаёт узлы как есть,
/// а складывает их читающий. Правила у потребителей разные — в сумме размера
/// ссылка весит свои байты, в счёте переноса не весит ничего, — и живут эти
/// правила в потребителе, а не здесь.
sealed class WalkEvent {
  const WalkEvent();
}

/// Очередной объект поддерева, включая сам корень обхода.
///
/// Каталоги приходят тоже — до того, как обойдено их содержимое. Размер у них
/// в этот миг ещё не известен; итог каталога придёт [WalkedDirectory].
class WalkedNode extends WalkEvent {
  const WalkedNode(this.node);

  final FsNode node;
}

/// Каталог, поддерево которого пройдено целиком, и его сумма.
///
/// Приходит **пост-порядком**: сперва содержимое, потом сам каталог. Только так
/// сумма окончательна, и прерванный обход не оставляет за собой полуправды.
class WalkedDirectory extends WalkEvent {
  const WalkedDirectory(this.directory, this.bytes);

  final DirectoryNode directory;

  /// Суммарный размер содержимого вместе с вложенными каталогами.
  final int bytes;

  String get path => directory.pathString;
}

/// Как часто обход отдаёт управление циклу событий.
///
/// То же значение и по той же причине, что у поиска: локальный провайдер читает
/// каталог синхронно, и без передышки обход занимает поток целиком.
const _breath = Duration(milliseconds: 16);

/// Байты объекта для суммы: неизвестный размер — ноль, каталог считается своим
/// содержимым, а не полем.
int _bytesOf(FsNode node) => node is DirectoryNode || node.size < 0 ? 0 : node.size;

/// Обход поддерева поверх [TreeProvider.listChildren] — один на все источники.
///
/// Провайдер берётся у **каждого** узла, поэтому набор из разных источников
/// (список находок) обходится целиком, а не провайдером первого узла.
///
/// Правила:
///
/// * ссылка не разыменовывается — [LinkNode] приходит узлом, спуск идёт только
///   в [DirectoryNode]; иначе одни и те же байты попали бы в сумму дважды;
/// * скрытые объекты считаются наравне с остальными: размер каталога от того,
///   показывает их панель или нет, не меняется;
/// * каталог, в который не пустили, обход не прекращает — его ветвь даёт ноль,
///   а обход идёт дальше;
/// * между каталогами управление возвращается циклу событий, поэтому интерфейс
///   остаётся отзывчивым, а отмена доходит до читающего сразу.
Stream<WalkEvent> walkTree(FsNode root, {Duration breath = _breath}) async* {
  final sinceBreath = Stopwatch()..start();

  Future<List<FsNode>> open(DirectoryNode directory) async {
    // Передышка **по времени**, а не по каталогам: каталоги бывают и на сто
    // записей, и на одну, и считать их пришлось бы наугад.
    if (sinceBreath.elapsed >= breath) {
      sinceBreath
        ..reset()
        ..start();
      // Именно [Future.delayed], а не `await null`: микрозадача выполняется
      // **до** кадра, и весь обход уложился бы в один оборот цикла.
      await Future<void>.delayed(Duration.zero);
    }

    try {
      return await directory.provider.listChildren(directory);
    } on Object {
      // Недоступный каталог — обычное дело посреди дерева, а не повод бросить
      // работу. Его ветвь просто останется пустой.
      return const [];
    }
  }

  yield WalkedNode(root);
  if (root is! DirectoryNode) {
    return;
  }

  // Свой стек вместо рекурсии: вложенный `yield*` пересылал бы каждое событие
  // через все открытые уровни, а событий на большом дереве сотни тысяч.
  final stack = <_Frame>[_Frame(root, await open(root))];

  while (stack.isNotEmpty) {
    final frame = stack.last;

    if (frame.index == frame.children.length) {
      stack.removeLast();
      yield WalkedDirectory(frame.directory, frame.bytes);
      if (stack.isNotEmpty) {
        stack.last.bytes += frame.bytes;
      }
      continue;
    }

    final child = frame.children[frame.index++];
    yield WalkedNode(child);

    if (child is DirectoryNode) {
      stack.add(_Frame(child, await open(child)));
    } else {
      frame.bytes += _bytesOf(child);
    }
  }
}

/// Открытый каталог: его содержимое, место обхода в нём и накопленная сумма.
class _Frame {
  _Frame(this.directory, this.children);

  final DirectoryNode directory;
  final List<FsNode> children;

  int index = 0;
  int bytes = 0;
}

/// Объекты задания: сколько их и сколько в них байт.
///
/// Тот же обход, что и у размера, но сложка другая — и в этом всё дело: перенос
/// считает **объекты работы**, а не занятое место, поэтому ссылка здесь байтов
/// не переносит (её копируют ссылкой), а у каталога их нет. Правило живёт тут,
/// у потребителя, а не в обходе.
///
/// [onEntry] зовётся на каждый объект поддерева, включая сам [root]. Исключение
/// из него наружу не гасится — так движок переноса прекращает подсчёт, когда
/// работа кончилась раньше него.
Future<void> countEntries(FsNode root, void Function(int bytes) onEntry) async {
  var isRoot = true;

  await for (final event in walkTree(root)) {
    if (event is! WalkedNode) {
      continue;
    }
    final node = event.node;
    // Сам корень считается тем, что он есть: сказали копировать ссылку —
    // ссылка и есть объект работы, со своими байтами.
    final counted = isRoot || (node is! DirectoryNode && node is! LinkNode);
    isRoot = false;
    onEntry(counted && node.size > 0 ? node.size : 0);
  }
}

/// Куда обход отдаёт окончательную сумму каждого пройденного каталога.
typedef DirectorySize = void Function(String path, int bytes);

/// Суммарный размер объектов вместе с содержимым каталогов — работой.
///
/// Обход долгий, поэтому работа не молчит до конца, а сообщает промежуточные
/// суммы: в [MultipleTransferOperationStatus.itemsTransferred] идёт то, что уже
/// насчитано, в `message` — имя объекта, который считают сейчас. Итог —
/// результат работы.
///
/// [onDirectory] зовётся на каждый пройденный каталог, включая вложенные, и
/// **только** с окончательной суммой: отменённый обход частичных сумм за собой
/// не оставляет.
Operation<List<FsNode>, int> sizeOperation({DirectorySize? onDirectory, Duration breath = _breath}) {
  return TaskOperation<List<FsNode>, int>((op, nodes) async {
    var total = 0;

    for (final node in nodes) {
      op.checkCanceled();

      await for (final event in walkTree(node, breath: breath)) {
        op.checkCanceled();
        switch (event) {
          case WalkedNode(node: final walked):
            final bytes = _bytesOf(walked);
            if (bytes > 0) {
              total += bytes;
              // Имя **корня** обхода, а не текущего объекта: строка хода
              // говорит, что считают, а не где обход идёт сию секунду.
              op.report(itemsTransferred: total, message: node.name);
            }
          case WalkedDirectory(:final path, :final bytes):
            onDirectory?.call(path, bytes);
        }
      }
    }

    return total;
  });
}
