import 'dart:async';

import 'package:fc_api/fc_api.dart';

import 'fs_node.dart';
import 'measured_sizes.dart';

/// Событие обхода поддерева.
///
/// **Сложку обход взял на себя** — и это смена прежнего договора («обход ничего
/// не решает за читающего»). Причина в том, что сложки две, а дерево одно:
/// считать их порознь значит обойти его дважды, а это и есть чинимый дефект
/// (`docs/spec/directory-sizes.md`, §12.3). Спорного решения обход при этом на
/// себя не берёт: правила расходятся только на листьях, а листья он и так видит
/// все до одного.
///
/// Что осталось у потребителя — правило про **корень задания**: сказали
/// копировать ссылку, и ссылка становится объектом работы со своими байтами.
/// Это правило не про дерево, а про задание, и живёт оно в [countEntries].
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
  const WalkedDirectory(this.directory, this.totals);

  final DirectoryNode directory;

  /// Три числа разом: занятое место, байты работы и объекты
  /// (`docs/spec/directory-sizes.md`, §12.2).
  final DirectoryTotals totals;

  /// Суммарный размер содержимого вместе с вложенными каталогами.
  int get bytes => totals.bytes;

  String get path => directory.pathString;
}

/// Каталог, который обходить не пришлось: числа уже были.
///
/// Отдельным событием, а не молчаливым пропуском: читающий обязан решить, что
/// он делает с переиспользованной ветвью, — и `switch` по событиям заставит его
/// это решить (`docs/spec/directory-sizes.md`, §12.3а).
class WalkedSubtree extends WalkEvent {
  const WalkedSubtree(this.directory, this.totals);

  final DirectoryNode directory;
  final DirectoryTotals totals;

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

/// Байты объекта для **задания**: ссылку копируют ссылкой, и переносить в ней
/// нечего; у каталога своих байтов нет.
int _workBytesOf(FsNode node) => node is DirectoryNode || node is LinkNode || node.size < 0 ? 0 : node.size;

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
/// [known] — способ спросить, посчитан ли каталог уже: не сама память, потому
/// что обходу незачем знать, кто за ней стоит. Не передали — обход идёт, как
/// ходил всегда, до последнего листа.
Stream<WalkEvent> walkTree(
  FsNode root, {
  Duration breath = _breath,
  DirectoryTotals? Function(DirectoryNode directory)? known,
}) async* {
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
      yield WalkedDirectory(frame.directory, frame.totals);
      if (stack.isNotEmpty) {
        stack.last.add(frame.totals);
      }
      continue;
    }

    final child = frame.children[frame.index++];

    if (child is DirectoryNode) {
      // Посчитанное поддерево не обходится второй раз — ради этого всё и
      // затевалось. Узел о нём всё равно сообщается: читающий должен знать, что
      // каталог в поддереве есть.
      if (known?.call(child) case final totals?) {
        yield WalkedNode(child);
        yield WalkedSubtree(child, totals);
        frame.add(totals);
        continue;
      }
      yield WalkedNode(child);
      stack.add(_Frame(child, await open(child)));
    } else {
      yield WalkedNode(child);
      frame.addLeaf(child);
    }
  }
}

/// Открытый каталог: его содержимое, место обхода в нём и накопленные числа.
class _Frame {
  _Frame(this.directory, this.children);

  final DirectoryNode directory;
  final List<FsNode> children;

  int index = 0;

  int _bytes = 0;
  int _workBytes = 0;

  /// Сам каталог — тоже объект работы: его создают на той стороне.
  int _entries = 1;

  DirectoryTotals get totals => DirectoryTotals(bytes: _bytes, workBytes: _workBytes, entries: _entries);

  void addLeaf(FsNode node) {
    _bytes += _bytesOf(node);
    _workBytes += _workBytesOf(node);
    _entries++;
  }

  void add(DirectoryTotals totals) {
    _bytes += totals.bytes;
    _workBytes += totals.workBytes;
    _entries += totals.entries;
  }
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
Future<void> countEntries(
  FsNode root,
  void Function(int bytes) onEntry, {
  DirectorySize? onDirectory,
  DirectoryTotals? Function(DirectoryNode directory)? known,
}) async {
  var isRoot = true;

  await for (final event in walkTree(root, known: known)) {
    switch (event) {
      case WalkedNode(node: final node):
        // Сам корень считается тем, что он есть: сказали копировать ссылку —
        // ссылка и есть объект работы, со своими байтами.
        final counted = isRoot || (node is! DirectoryNode && node is! LinkNode);
        isRoot = false;
        onEntry(counted && node.size > 0 ? node.size : 0);
      case WalkedSubtree(:final directory, :final totals):
        // Поддерево не обходили — его числа приходят разом. Объекты всё равно
        // считаются поштучно: счётчик работы меряет их, а не каталоги.
        onDirectory?.call(directory, totals);
        onEntry(totals.workBytes);
        for (var i = 1; i < totals.entries; i++) {
          onEntry(0);
        }
      case WalkedDirectory(:final directory, :final totals):
        onDirectory?.call(directory, totals);
    }
  }
}

/// Куда обход отдаёт окончательные числа каждого пройденного каталога.
///
/// Узлом, а не путём: общая память различает каталоги по провайдеру, и одного
/// пути ей мало (`docs/spec/directory-sizes.md`, §12.7).
typedef DirectorySize = void Function(DirectoryNode directory, DirectoryTotals totals);

/// Суммарный размер объектов вместе с содержимым каталогов — работой.
///
/// Обход долгий, поэтому работа не молчит до конца, а сообщает промежуточные
/// суммы: в [MultipleTransferOperationStatus.itemsTransferred] идёт то, что уже
/// насчитано, в `message` — имя объекта, который считают сейчас. Итог —
/// результат работы.
///
/// [onDirectory] зовётся на каждый каталог с окончательным числом — и на
/// пройденный, и на тот, чьи числа взяты готовыми, — включая вложенные.
/// Частичных сумм за собой отменённый обход не оставляет.
Operation<List<FsNode>, int> sizeOperation({
  DirectorySize? onDirectory,
  DirectoryTotals? Function(DirectoryNode directory)? known,
  Duration breath = _breath,
}) {
  return TaskOperation<List<FsNode>, int>((op, nodes) async {
    var total = 0;

    for (final node in nodes) {
      op.checkCanceled();

      await for (final event in walkTree(node, breath: breath, known: known)) {
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
          case WalkedSubtree(:final directory, :final totals):
            // Поддерево не обходили: его содержимое в сумму приходит разом, а
            // сам каталог как узел уже пришёл нулём — двойного счёта нет.
            total += totals.bytes;
            op.report(itemsTransferred: total, message: node.name);
            // И о переиспользованном каталоге читающему говорят тоже: число у
            // него окончательное, а строке в панели оно нужно не меньше.
            onDirectory?.call(directory, totals);
          case WalkedDirectory(:final directory, :final totals):
            onDirectory?.call(directory, totals);
        }
      }
    }

    return total;
  });
}
