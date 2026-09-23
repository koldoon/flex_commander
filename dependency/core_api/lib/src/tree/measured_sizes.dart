import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'fs_node.dart';
import 'node_path.dart';
import 'tree_provider.dart';

/// Три числа одного каталога: их считает **один** проход.
///
/// Считать их порознь — это и есть та самая двойная ходьба, ради которой всё
/// затевалось (`docs/spec/directory-sizes.md`, §12.3). А смешивать нельзя:
/// занятое место и байты работы расходятся на ссылках, и сложенные вместе они
/// дают тихо неверные числа там, где сегодня верные (§12.2).
class DirectoryTotals {
  const DirectoryTotals({required this.bytes, required this.workBytes, required this.entries});

  /// Занятое место: у ссылки — её собственные байты, у каталога — ноль,
  /// потому что каталог весь в содержимом. Это то, что показывает колонка.
  final int bytes;

  /// Байты работы: ссылку копируют ссылкой, и переносить в ней нечего.
  final int workBytes;

  /// Объекты работы, считая сам каталог.
  final int entries;

  @override
  bool operator ==(Object other) =>
      other is DirectoryTotals && other.bytes == bytes && other.workBytes == workBytes && other.entries == entries;

  @override
  int get hashCode => Object.hash(bytes, workBytes, entries);

  @override
  String toString() => 'DirectoryTotals(bytes: $bytes, work: $workBytes, entries: $entries)';
}

/// Идущий обход, к которому можно присоединиться.
///
/// Заводит его тот, кто первым спросил у памяти и ничего не нашёл; остальные
/// **присоединяются**, а не заводят второй (`docs/spec/directory-sizes.md`,
/// §12.3а).
class MeasuredWalk {
  MeasuredWalk({required this.cancel});

  /// Чем прекратить обход, когда он перестал быть нужен **всем**.
  final void Function() cancel;

  final Completer<DirectoryTotals?> _done = Completer<DirectoryTotals?>();

  /// Сколько сторон ждут этого обхода. Последняя уходящая гасит свет.
  int _interest = 0;

  Future<DirectoryTotals?> get done => _done.future;

  /// Обход кончился итогом.
  void finish(DirectoryTotals totals) {
    if (!_done.isCompleted) {
      _done.complete(totals);
    }
  }

  /// Обход кончился ничем: отмена, ошибка, исчезнувший каталог. Ждущие узнают
  /// об этом `null` — «считай сам, если тебе всё ещё надо».
  void abandon() {
    if (!_done.isCompleted) {
      _done.complete(null);
    }
  }
}

/// Память посчитанного: итоги законченных обходов и обходы, идущие прямо
/// сейчас.
///
/// Спецификация — `docs/spec/directory-sizes.md`, §12.
///
/// Одна на приложение, и потому лежит здесь, а не в ядре рядом с кешем
/// каталогов: потребителей у неё два, и второй — движок переноса, который про
/// ядро не знает и знать не должен.
///
/// **Частичных сумм память не видит никогда.** Растущая сумма идущего обхода —
/// дело того, кто его завёл: половина, застывшая как итог, — ложь (§7).
class MeasuredSizes {
  /// Сколько **попутных** каталогов помнить: тех, через которые обход просто
  /// прошёл. Числом, а не настройкой: запись — это три числа, а не список
  /// узлов, и крутить её человеку незачем.
  ///
  /// Не `const` затем, чтобы проверке не приходилось заводить дерево на четыре
  /// тысячи каталогов ради одного вытеснения. Тем же приёмом живут предел
  /// раскрытия дерева и окно отчётов работы.
  @visibleForTesting
  static int limit = 4096;

  /// Сколько помнить **просьб** — каталогов, которые считать попросили.
  ///
  /// Очередь отдельная, и это главное в пределе: попутных подкаталогов у
  /// одного большого дерева десятки тысяч, а просьб — единицы. В общей очереди
  /// одно дерево выбрасывало всё, что человек насчитал до него, и в колонке
  /// снова стоял прочерк (§12.3).
  @visibleForTesting
  static int askedLimit = 1024;

  /// Просьбы: их вытесняет только другая просьба.
  final LinkedHashMap<String, _Measured> _asked = LinkedHashMap();

  /// Попутное: досталось даром, даром и теряется.
  final LinkedHashMap<String, _Measured> _passed = LinkedHashMap();

  /// Идущие обходы по тем же путям.
  final Map<String, MeasuredWalk> _walks = {};

  final List<void Function(Set<String> paths)> _listeners = [];

  /// Сколько итогов помнится сейчас. Нужно проверкам.
  int get length => _asked.length + _passed.length;

  /// Сколько из них — просьбы.
  int get askedLength => _asked.length;

  /// Итог по каталогу; null — итога нет (но обход может идти, см. [claim]).
  ///
  /// Чужая запись не отдаётся: одинаковые пути у двух подключений к одному
  /// хосту — разные каталоги, и различает их провайдер, а не строка.
  DirectoryTotals? take(DirectoryNode dir) => at(dir.pathString, dir.provider);

  /// То же, но по пути и провайдеру: узла под рукой не всегда есть.
  ///
  /// Так спрашивает панель, когда та сторона просит числа для строк: путей у
  /// неё список, а провайдер один на всю панель.
  DirectoryTotals? at(String path, TreeProvider provider) {
    final queue = _asked.containsKey(path) ? _asked : _passed;
    final entry = queue[path];
    if (entry == null || !identical(entry.provider, provider)) {
      return null;
    }
    // Обратно в конец своей очереди: вытесняется давно не нужное, а не давно
    // посчитанное.
    queue.remove(path);
    queue[path] = entry;
    return entry.totals;
  }

  /// Взять посчитанное, присоединиться к идущему обходу или завести свой.
  ///
  /// Три ответа памяти на один вопрос (§12.3а). Возвращает null, если обход
  /// кончился ничем: отменили, не пустили, каталог исчез.
  ///
  /// [start] зовётся **только** когда обходить и правда некому — так второй
  /// спрашивающий не заводит второго обхода того же дерева.
  Future<DirectoryTotals?> claim(DirectoryNode dir, MeasuredWalk Function() start) {
    if (take(dir) case final totals?) {
      return Future.value(totals);
    }
    final path = dir.pathString;
    final walk = _walks[path] ?? (_walks[path] = start());
    walk._interest++;
    return walk.done;
  }

  /// Сказать памяти о своём обходе, не дожидаясь его: так панель объявляет
  /// обход, итога которого сама ждёт своим способом.
  ///
  /// Возвращает уже идущий обход, если он есть, — заводить второй незачем.
  MeasuredWalk announce(DirectoryNode dir, MeasuredWalk Function() start) {
    final path = dir.pathString;
    final walk = _walks[path] ?? (_walks[path] = start());
    walk._interest++;
    return walk;
  }

  /// Интерес кончился: обход отменяется, если больше его никто не ждёт.
  void drop(DirectoryNode dir, MeasuredWalk walk) {
    walk._interest--;
    if (walk._interest > 0) {
      return;
    }
    _walks.remove(dir.pathString);
    walk.cancel();
    walk.abandon();
  }

  /// Обход кончился итогом: он ложится в память, а ждущие получают числа.
  ///
  /// [asked] — этот каталог считать **просили**: он корень обхода, его число
  /// человек видит в колонке. Попутные подкаталоги приходят сюда же, но своей
  /// очередью, и вытесняют только друг друга (§12.3).
  void remember(DirectoryNode dir, DirectoryTotals totals, {bool asked = false}) {
    final path = dir.pathString;
    // Просьбу попутным проходом не разжаловать: считать этот каталог просили,
    // и то, что обход прошёл через него второй раз по дороге в соседний, дела
    // не меняет.
    final keep = asked || _asked.containsKey(path);
    _asked.remove(path);
    _passed.remove(path);

    final queue = keep ? _asked : _passed;
    final edge = keep ? askedLimit : limit;
    while (queue.length >= edge) {
      queue.remove(queue.keys.first);
    }
    queue[path] = _Measured(totals, dir.provider);

    final walk = _walks.remove(path);
    walk?.finish(totals);
  }

  /// Обход кончился ничем — следа он не оставляет.
  void abandon(DirectoryNode dir) {
    _walks.remove(dir.pathString)?.abandon();
  }

  /// Забыть каталог, всё под ним и всех его предков.
  ///
  /// Предки — то, чего не забывал никто: скопировали в подкаталог, а сумма
  /// родителя осталась вчерашней (§12.4).
  ///
  /// [withSubtree] false — забыть только сам каталог и предков: так просит
  /// событие слежения, которое про поддерево ничего и не говорило.
  void forget(String path, {bool withSubtree = true}) {
    final gone = <String>{};
    for (final queue in [_asked, _passed]) {
      for (final key in queue.keys.toList()) {
        if (key == path || (withSubtree && isUnder(key, path)) || isUnder(path, key)) {
          queue.remove(key);
          gone.add(key);
        }
      }
    }
    if (gone.isEmpty) {
      return;
    }
    for (final listener in _listeners.toList()) {
      listener(gone);
    }
  }

  /// Провайдера закрыли: всё, что он считал, — числа о мертвеце.
  void forgetProvider(TreeProvider provider) {
    final gone = <String>{};
    for (final queue in [_asked, _passed]) {
      queue.removeWhere((key, entry) {
        if (!identical(entry.provider, provider)) {
          return false;
        }
        gone.add(key);
        return true;
      });
    }
    if (gone.isEmpty) {
      return;
    }
    for (final listener in _listeners.toList()) {
      listener(gone);
    }
  }

  /// Кому рассказывать о забытом.
  ///
  /// Число живёт не только здесь: панель пишет его в свои строки. Панель,
  /// стоящая **не** в том каталоге, который забыли, перечитывания не получит —
  /// и рисовала бы вчерашнее, не узнай она об этом.
  /// Возвращает способ отписаться: память одна на приложение, а панели
  /// приходят и уходят — забытая подписка держала бы закрытую сессию.
  void Function() onForgotten(void Function(Set<String> paths) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void clear() {
    _asked.clear();
    _passed.clear();
    _walks.clear();
  }
}

/// Лежит ли [path] внутри [parent].
///
/// Разбором, а не сравнением строк: у смонтированного провайдера разделитель
/// двоеточие (`/a.zip:zip:/inner`), и проверка по `'$parent/'` промахнулась бы
/// мимо всего содержимого архива — а заодно посчитала бы `/home/doc2` лежащим
/// в `/home/doc`.
bool isUnder(String path, String parent) => ancestorsOf(path).contains(parent);

/// Все предки пути, от ближайшего к дальнему.
///
/// Для `/a.zip:zip:/inner/x` это `/a.zip:zip:/inner`, `/a.zip:zip:/` и сам
/// `/a.zip`: файл архива честно оказывается предком своего содержимого — в
/// него ведь и пишут, когда пишут внутрь.
Iterable<String> ancestorsOf(String path) sync* {
  final parts = [...NodePath.parse(path).parts];

  while (parts.isNotEmpty) {
    final part = parts.removeLast();
    var at = part.path;

    while (at.isNotEmpty && at != '/') {
      final cut = at.lastIndexOf('/');
      at = cut <= 0 ? '/' : at.substring(0, cut);
      yield NodePath([...parts, NodePathPart(part.scheme, at)]).toString();
    }

    // Корень вложенного провайдера исчерпан: дальше предок — сам файл, на
    // котором он смонтирован, и он уже лежит в оставшихся частях.
    if (parts.isNotEmpty) {
      yield NodePath([...parts]).toString();
    }
  }
}

/// Посчитанное: три числа и чей это провайдер.
class _Measured {
  _Measured(this.totals, this.provider);

  final DirectoryTotals totals;

  /// По нему запись выбрасывается, когда провайдер закрыт, и по нему же чужая
  /// не отдаётся. Аренды за ссылкой нет — как и у кеша каталогов.
  final TreeProvider provider;
}
