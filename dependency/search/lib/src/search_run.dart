import 'dart:collection';

import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:flutter/foundation.dart';

import 'search_query.dart';

/// Обход дерева в поисках имён.
///
/// **Обычная работа поверх провайдера** (`listChildren`), а не поход по диску:
/// поэтому поиск сразу работает и в архиве, и по `ssh` — там, где стоит панель.
///
/// Найденное отдаётся **по ходу** ([onFound]), а не в конце: на большом дереве
/// первые попадания видны сразу, и обычно этого довольно. Итог работы — тот же
/// список целиком, для тех, кому нужен только он.
class SearchRun {
  /// Как часто обход отдаёт управление интерфейсу.
  ///
  /// Восемь миллисекунд — половина кадра при шестидесяти в секунду: реже
  /// незачем, чаще дороже пользы.
  ///
  /// Не `const` затем, чтобы замер мог спросить «а сколько стоит дышать»:
  /// сравнивать вдох с его отсутствием надо на одном и том же коде, иначе в
  /// разницу попадает всё остальное — сборка узлов, например
  /// (`test/performance/heavy_work_bench_test.dart`).
  @visibleForTesting
  static Duration breath = const Duration(milliseconds: 8);

  /// Работа, которую остаётся запустить: `start` — и она пойдёт.
  static Operation<SearchQuery, List<FsNode>> from(DirectoryNode where, {required void Function(FsNode) onFound}) {
    return TaskOperation<SearchQuery, List<FsNode>>((op, query) async {
      final mask = FileMask.parse(query.mask);
      final found = <FsNode>[];
      if (mask.isEmpty) {
        // Пустая маска не совпадает ни с чем — обходить дерево незачем.
        return found;
      }

      // Очередь, а не список: `removeAt(0)` сдвигает весь хвост, а каталогов
      // в большом дереве десятки тысяч.
      final queue = Queue<DirectoryNode>()..add(where);
      final sinceBreath = Stopwatch()..start();
      while (queue.isNotEmpty) {
        // Прерывание проверяется на каждом каталоге, а не на каждом файле:
        // между каталогами и есть настоящее ожидание — чтение с диска или из
        // сети.
        await op.checkpoint();

        // …и здесь же обход отдаёт управление циклу событий.
        //
        // **Иначе он занимает поток целиком.** Локальный провайдер читает
        // каталог **синхронно** (`readDirectoryBlocking`), а `await` над тем,
        // что уже готово, — это микрозадача; микрозадачи же выполняются
        // **до** кадра. Весь обход укладывался в один оборот цикла: ни кадра,
        // ни таймера, пока он не кончится. Живьём — `*.dart` по рабочему
        // каталогу вешал приложение намертво, ограничитель перерисовки не
        // спасал (его таймеру неоткуда было сработать), и даже прервать поиск
        // было нечем: просьба об отмене приходит из той же очереди.
        //
        // Именно [Future.delayed], а не `await null`: таймер уводит обход в
        // очередь событий, где его ждут кадр, нажатия и прочие таймеры.
        //
        // По времени, а не по каталогам: каталоги бывают и на сто записей, и
        // на одну, и считать их пришлось бы наугад.
        if (sinceBreath.elapsed >= breath) {
          sinceBreath
            ..reset()
            ..start();
          await Future<void>.delayed(Duration.zero);
        }

        final dir = queue.removeFirst();
        // Путь **для человека**: в строке хода работы он и стоит. Машинный
        // (`pathString`) несёт схемы провайдеров — `…/a.zip:zip:/inner`, — и
        // читать их в этой строке незачем.
        op.report(message: dir.displayPath, indeterminate: true, itemsTransferred: found.length);

        final List<FsNode> children;
        try {
          children = await dir.provider.listChildren(dir);
        } on Object {
          // Каталог, в который не пустили, поиск не прекращает: непрочитанный
          // `/root` посреди дерева — обычное дело, а не повод бросить работу.
          continue;
        }

        for (final node in children) {
          if (!query.hidden && node.name.startsWith('.')) {
            continue;
          }
          if (mask.matches(node.name)) {
            found.add(node);
            onFound(node);
          }
          // Каталог может и сам подойти под маску, и содержать подходящее:
          // одно другому не мешает.
          if (query.recursive && node is DirectoryNode) {
            queue.add(node);
          }
        }
      }

      // Последнее слово работы — итог: с ним она и остаётся в полоске фоновых
      // работ, если окно закрыли. «Ищу в таком-то каталоге» у законченной
      // работы читалось бы как «всё ещё ищу».
      op.report(message: 'Found ${found.length}', itemsTransferred: found.length);
      return found;
    });
  }
}
