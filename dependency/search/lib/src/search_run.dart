import 'dart:collection';

import 'package:fc_api/fc_api.dart';
import 'package:fc_content_types/fc_content_types.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'content_rule.dart';
import 'content_scan.dart';
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

  /// Сколько архивов вложения разворачивать: `1` — сам архив обходится, а
  /// архив внутри него уже нет.
  ///
  /// Константой в коде, а не настройкой — по той же причине, что и предел
  /// памяти посчитанных размеров: число, которое нечем объяснить человеку, в
  /// окне настроек лишнее. Попросят — заведём
  /// (`docs/spec/file-search.md`, §12.4).
  @visibleForTesting
  static int archiveDepth = 1;

  /// Работа, которую остаётся запустить: `start` — и она пойдёт.
  ///
  /// [registry] — чем открывать архивы по дороге; null — нечем, и флажок «в
  /// архивах» ничего не меняет (§12.2).
  static Operation<SearchQuery, List<FsNode>> from(
    DirectoryNode where, {
    required void Function(List<FsNode>) onFound,
    Strings? strings,
    ProviderRegistry? registry,
  }) {
    final said = strings ?? StringsRegistry();
    return TaskOperation<SearchQuery, List<FsNode>>((op, query) async {
      final name = query.name;
      final ignored = query.ignored;
      final content = query.contentRule;
      final found = <FsNode>[];
      final batch = <FsNode>[];
      void flush() {
        if (batch.isNotEmpty) {
          onFound(List.of(batch));
          batch.clear();
        }
      }

      // Пустое имя при заданном содержимом значит «любое»: человек, набравший
      // только содержимое, просит искать везде, а не нигде (§11.2).
      if ((name.isEmpty && content.isEmpty) || !name.isValid || !content.isValid) {
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

      /// Обходит одну стопку до конца. Своя стопка — у каждого архива: так
      /// аренда живёт ровно пока ветвь обходят (§12.3).
      ///
      /// [depth] — сколько архивов вложения уже открыто.
      Future<void> walk(Queue<DirectoryNode> stack, int depth) async {
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
          // Архивы этого каталога — их обходят своей стопкой, в том порядке, в
          // каком их вернул источник.
          final dive = <FsNode>[];
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
            // Имя отбирает первым: маска дешева, чтение дорого. Файл, не
            // прошедший по имени, размеру или дате, не читается вовсе (§11.2).
            if ((name.isEmpty || name.matches(node.name)) && _fits(node, query)) {
              if (content.isEmpty) {
                found.add(node);
                batch.add(node);
              } else if (node is! DirectoryNode && await _hasInside(node, content, op)) {
                found.add(node);
                batch.add(node);
              }
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
          if (query.archives && registry != null && depth < archiveDepth) {
            for (final node in children) {
              if (registry.schemeFor(node) != null) {
                dive.add(node);
              }
            }
          }
          // Архивы — до подкаталогов: находка из архива, лежащего здесь, стоит
          // ближе к этому каталогу, чем всё, что глубже.
          for (final archive in dive) {
            await op.checkpoint();
            await _inside(op, registry!, archive, (root) => walk(Queue<DirectoryNode>()..add(root), depth + 1));
          }
          // Задом наперёд: стопка отдаёт последнее, а спускаться надо в первый
          // подкаталог — в том порядке, в каком их вернул источник.
          for (final dir in descend.reversed) {
            stack.addFirst(dir);
          }
        }
      }

      await walk(stack, 0);

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

  /// Монтирует архив, отдаёт его корень обходу и **отпускает аренду**.
  ///
  /// Отпускание в `finally`: прервали поиск посреди архива — держать его
  /// больше некому (§12.3). Архив, который не открылся, не дочитался или
  /// спросил пароль, которого некому ввести, пропускается — как пропускается
  /// нечитаемый каталог (§12.5).
  static Future<void> _inside(
    OperationContext op,
    ProviderRegistry registry,
    FsNode archive,
    Future<void> Function(DirectoryNode root) walk,
  ) async {
    final scheme = registry.schemeFor(archive);
    if (scheme == null) {
      return;
    }
    final ProviderLease lease;
    try {
      lease = await registry.acquire().run(AcquireParams(scheme, archive));
    } on Object {
      return;
    }
    try {
      await walk(lease.provider.rootDirectory);
    } on OperationCanceled {
      rethrow;
    } on Object {
      // Оглавление оборвалось на середине — дальше по внешнему дереву.
    } finally {
      await lease.release();
    }
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

  /// Есть ли искомое **внутри** файла.
  ///
  /// Читается кусками, потоком: файл бывает больше памяти. Двоичное отсеивается
  /// по началу — тем же правилом, что у службы типов (`textOrBinary`), и голова
  /// при этом не пропадает: она же первый кусок поиска (§11.2).
  ///
  /// Отмена проверяется **между кусками**: файл в гигабайт делает проверку раз
  /// на каталог бесполезной.
  static Future<bool> _hasInside(FsNode node, ContentRule rule, TaskOperation<Object?, Object?> op) async {
    final provider = node.provider;
    if (provider is! FileContentProvider) {
      return false;
    }

    final scan = ContentScan(rule);
    var head = <int>[];
    var decided = false;
    try {
      // Приведение явное, как и в ядре (`content_hub.dart`): `TreeProvider` —
      // интерфейс, и умение читать объявлено отдельным.
      await for (final chunk in await (provider as FileContentProvider).openRead(node)) {
        await op.checkpoint();

        if (!decided) {
          head = head.isEmpty ? chunk : [...head, ...chunk];
          if (head.length < headSize) {
            // Голову дочитываем целиком: решение «текст или двоичное» по
            // половине сигнатуры было бы гаданием.
            continue;
          }
          decided = true;
          if (_looksBinary(head, rule.anyCharset)) {
            return false;
          }
          if (scan.feed(head)) {
            return true;
          }
          continue;
        }

        if (scan.feed(chunk)) {
          return true;
        }
      }
    } on Object {
      // Файл, который не дали прочесть, поиск не прекращает — как и каталог.
      return false;
    }

    // Файл кончился, а голова так и не набралась: короткий файл решается тем
    // же правилом и ищется целиком.
    if (!decided) {
      if (_looksBinary(head, rule.anyCharset)) {
        return false;
      }
      if (scan.feed(head)) {
        return true;
      }
    }
    return scan.close();
  }

  /// Сколько байт хватает, чтобы решить «текст или двоичное».
  ///
  /// Столько же берёт служба типов: правило одно, и число при нём то же.
  static const int headSize = 4096;

  /// Двоичное ли начало.
  ///
  /// [anyCharset] — когда ищут в любых кодировках, остаётся **только** правило
  /// нулевого байта. Обычное правило объявляет двоичным всё, что не разбирается
  /// как UTF-8, — а текст в CP1251 как раз таким и приходит: отсеивать его тем
  /// же ситом значило бы обещать поиск в других кодировках и не искать в них
  /// ни разу (§11.2).
  static bool _looksBinary(List<int> head, bool anyCharset) {
    if (head.isEmpty) {
      return false;
    }
    if (anyCharset) {
      return head.contains(0);
    }
    return textOrBinary(Uint8List.fromList(head)).group == ContentGroup.binary;
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
