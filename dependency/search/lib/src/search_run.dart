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
///
/// Пачками, а не по одной: находки приходят быстрее, чем экран успевает
/// обновиться, а за границей каждая была бы ещё и отдельным сообщением. Пачка
/// уходит на том же вдохе, которым обход отдаёт управление циклу событий, —
/// чаще смотреть всё равно незачем.
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
  static Operation<SearchQuery, List<FsNode>> from(
    DirectoryNode where, {
    required void Function(List<FsNode>) onFound,
    Strings? strings,
  }) {
    final said = strings ?? StringsRegistry();
    return TaskOperation<SearchQuery, List<FsNode>>((op, query) async {
      final name = query.name;
      final ignored = query.ignored;
      final found = <FsNode>[];
      final batch = <FsNode>[];
      void flush() {
        if (batch.isNotEmpty) {
          onFound(List.of(batch));
          batch.clear();
        }
      }

      if (name.isEmpty || !name.isValid) {
        // Пустое правило не совпадает ни с чем, неверное выражение — тем
        // более: обходить дерево незачем. Про неверное человек узнаёт раньше,
        // у поля (`docs/spec/file-search.md`, §10.2), — здесь это последняя
        // застава.
        return found;
      }

      // **В глубину, а не в ширину** — и по порядку: каталог, потом первый его
      // подкаталог целиком, потом второй.
      //
      // Так находки приходят в том же порядке, в каком дерево находок
      // разворачивается на экране, и новое всегда оказывается **в конце**.
      // Обход в ширину этого не даёт: находка из глубины приходит позже, а
      // место её — внутри ветви, нарисованной выше, и всё, что ниже, съезжает.
      // Живьём это выглядело так, что список скачет (`docs/spec/file-search.md`,
      // §4).
      //
      // Стопка, а не список: `removeAt(0)` сдвигает весь хвост, а каталогов в
      // большом дереве десятки тысяч.
      final stack = Queue<DirectoryNode>()..add(where);

      // Где уже были — настоящими путями.
      //
      // Без этого обход по ссылкам не заканчивается никогда: `a → b → a` водит
      // по кругу, а две разные ссылки на один каталог — это один каталог
      // (§10.4). Память живёт ровно столько, сколько обход.
      final visited = <String>{_identityOf(where)};
      final sinceBreath = Stopwatch()..start();
      while (stack.isNotEmpty) {
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
          flush();
          await Future<void>.delayed(Duration.zero);
        }

        final dir = stack.removeFirst();
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

        final descend = <DirectoryNode>[];
        for (final node in children) {
          if (!query.hidden && node.name.startsWith('.')) {
            continue;
          }
          // Исключённый каталог убирается из поиска целиком — и спуск, и сама
          // находка: «не заходить, но показать» читалось бы как ошибка
          // (§10.3). Сличается **имя**, а не путь: человек пишет
          // `node_modules`, а не `**/node_modules`.
          if (!ignored.isEmpty && node is DirectoryNode && ignored.matches(node.name)) {
            continue;
          }
          if (name.matches(node.name) && _fits(node, query)) {
            found.add(node);
            batch.add(node);
          }
          if (!query.recursive) {
            continue;
          }
          // Каталог может и сам подойти под правило, и содержать подходящее:
          // одно другому не мешает.
          if (node is DirectoryNode) {
            if (visited.add(_identityOf(node))) {
              descend.add(node);
            }
            continue;
          }
          // Ссылка, ведущая в каталог, — тоже дорога вниз, если о том просили.
          // Ведёт ли она в каталог, видно **без** разыменования: `targetType`
          // приходит вместе с чтением каталога, а `resolve` стоит похода к
          // источнику (§10.4).
          if (query.followLinks && node is LinkNode && node.isDirectoryLink) {
            final target = await _targetOf(node);
            if (target != null && visited.add(_identityOf(target))) {
              descend.add(target);
            }
          }
        }
        // Задом наперёд: стопка отдаёт последнее, а спускаться надо в первый
        // подкаталог — в том порядке, в каком их вернул источник.
        for (final dir in descend.reversed) {
          stack.addFirst(dir);
        }
      }

      // Последняя пачка — до итога: «нашлось столько-то» не должно опережать
      // самих находок.
      flush();

      // Последнее слово работы — итог: с ним она и остаётся в полоске фоновых
      // работ, если окно закрыли. «Ищу в таком-то каталоге» у законченной
      // работы читалось бы как «всё ещё ищу».
      op.report(message: said.tr('Found: {count}', args: {'count': found.length}), itemsTransferred: found.length);
      return found;
    });
  }

  /// Подходит ли объект по размеру и дате.
  ///
  /// **Каталоги условие размера не отбирает**: их размер без обхода неизвестен,
  /// и требовать его значило бы обойти всё дерево ради отбора
  /// (`docs/spec/file-search.md`, §10.5). Незаданный конец не ограничивает
  /// ничего.
  static bool _fits(FsNode node, SearchQuery query) {
    if (node is! DirectoryNode) {
      final size = node.size;
      if (size >= 0) {
        if (query.sizeFrom case final from? when size < from) {
          return false;
        }
        if (query.sizeTo case final to? when size > to) {
          return false;
        }
      }
    }
    final changed = node is FileNode ? node.modified : null;
    if (query.changedAfter case final after?) {
      if (changed == null || changed.isBefore(after)) {
        return false;
      }
    }
    if (query.changedBefore case final before?) {
      if (changed == null || changed.isAfter(before)) {
        return false;
      }
    }
    return true;
  }

  /// Чем каталог опознаётся в памяти пройденного.
  ///
  /// **Настоящим путём**, если источник его знает: две ссылки на один каталог
  /// — это один каталог, а по адресу внутри дерева они разные. Не знает —
  /// адресом: у архива и у сервера он и есть единственное имя узла.
  static String _identityOf(FsNode node) {
    if (node.provider case final RealPathSource source) {
      final real = source.realPathOf(node);
      if (real.isNotEmpty) {
        return real;
      }
    }
    return node.pathString;
  }

  /// Каталог, в который ведёт ссылка; null — не ведёт или не дошли.
  ///
  /// Разыменование стоит похода к источнику, поэтому зовётся оно **только**
  /// когда вниз и правда идём. Битая ссылка — не ошибка обхода: он идёт дальше.
  static Future<DirectoryNode?> _targetOf(LinkNode link) async {
    try {
      final target = link.target ?? await link.resolve().run(link);
      return target is DirectoryNode ? target : null;
    } on Object {
      return null;
    }
  }
}
