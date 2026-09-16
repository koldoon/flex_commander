import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

/// Миниатюры: очередь, пул и кеш.
///
/// Спецификация — `docs/spec/file-thumbnails.md`.
///
/// Устроено как чтение типов по содержимому (`content-types.md`), и не
/// случайно: задача та же — дорогой вопрос о каждой видимой строке. Разница
/// одна, и она в кеше: ответы здесь весят не одинаково, и считать их записями
/// нельзя (§7 спеки).
class ThumbnailStore {
  ThumbnailStore({
    required SystemThumbnails thumbnails,
    int concurrency = defaultConcurrency,
    int budget = defaultBudget,
  }) : _thumbnails = thumbnails,
       _concurrency = concurrency,
       _budget = budget;

  /// Сколько вопросов идёт разом.
  ///
  /// Меньше — и экран заполняется рывками; больше — и полуторасекундный `pdf`
  /// находит себе трёх товарищей и занимает всё (замеры — §2 спеки).
  static const int defaultConcurrency = 4;

  /// Сколько приехавших байтов помним.
  ///
  /// Байтами, а не записями: миниатюра при 128 точках на удвоенном экране это
  /// картинка 256×256, и полтысячи таких съели бы память молча.
  static const int defaultBudget = 32 * 1024 * 1024;

  final SystemThumbnails _thumbnails;
  final int _concurrency;
  final int _budget;

  /// Приехавшее: ключ → картинка. Порядок вставки и есть порядок вытеснения.
  final LinkedHashMap<String, _Kept> _kept = LinkedHashMap();

  /// То, у чего миниатюры нет. Второй раз в этот сеанс не спрашиваем: плитка
  /// перерисовывается по многу раз, и каждая перерисовка ломилась бы в систему.
  final Set<String> _blank = {};

  /// Идущее и стоящее в очереди: ключ → обещание. Отсюда и берётся тот же
  /// ответ на повторный вопрос.
  final Map<String, Future<void>> _pending = {};

  final Queue<_Request> _queue = Queue();
  int _running = 0;

  /// Сколько байтов лежит в кеше сейчас — на случай проверки и для порядка.
  int get bytes => _kept.values.fold(0, (sum, kept) => sum + kept.bytes);

  /// Готовый ответ; null — либо не спрашивали, либо миниатюры нет.
  ///
  /// Спрошенное и не отвеченное — тоже null: рисовать пока нечем, и строка
  /// покажет то, что знает по имени.
  ImageProvider? known(FileEntry entry, int pixels) => _kept[_keyOf(entry, pixels)]?.image;

  /// Есть ли смысл спрашивать: у местного файла — да, один раз.
  bool wants(FileEntry entry, int pixels) {
    if (entry.realPath.isEmpty || entry.kind != EntryKind.file) {
      return false;
    }
    final key = _keyOf(entry, pixels);
    return !_kept.containsKey(key) && !_blank.contains(key);
  }

  /// Спросить систему. Обещание кончается, когда ответ лёг в кеш.
  Future<void> ask(FileEntry entry, int pixels, {bool Function()? stillWanted}) {
    final key = _keyOf(entry, pixels);
    final pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    final request = _Request(key, entry.realPath, pixels, stillWanted);
    _pending[key] = request.completer.future;
    _queue.add(request);
    _pump();
    return request.completer.future;
  }

  /// Занять свободные места в пуле.
  void _pump() {
    while (_running < _concurrency && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      // Плитка уехала с экрана, пока вопрос стоял в очереди: спрашивать не о
      // чем, и запоминать по ней нечего — файл не отказал, его просто не
      // спросили.
      if (request.stillWanted?.call() == false) {
        _pending.remove(request.key);
        request.completer.complete();
        continue;
      }
      _running++;
      unawaited(_fetch(request));
    }
  }

  Future<void> _fetch(_Request request) async {
    Uint8List? bytes;
    try {
      bytes = await _thumbnails.forPath(request.path, pixels: request.pixels);
    } on Object {
      // Канала нет, платформа не умеет, файл исчез — значок возьмётся
      // следующим правилом, и это не повод падать.
      bytes = null;
    }

    _running--;
    if (bytes == null || bytes.isEmpty) {
      _blank.add(request.key);
    } else {
      _remember(request.key, bytes);
    }
    _pending.remove(request.key);
    request.completer.complete();
    _pump();
  }

  void _remember(String key, Uint8List bytes) {
    _kept[key] = _Kept(MemoryImage(bytes), bytes.length);
    var held = this.bytes;
    while (held > _budget && _kept.length > 1) {
      final oldest = _kept.keys.first;
      held -= _kept[oldest]!.bytes;
      _kept.remove(oldest);
    }
  }

  /// Путь, время правки и размер в пикселях.
  ///
  /// Без времени правки изменённый файл показывал бы вчерашнюю картинку, а это
  /// худший вид ошибки: правдоподобный.
  static String _keyOf(FileEntry entry, int pixels) =>
      '${entry.realPath}|${entry.modified?.millisecondsSinceEpoch ?? 0}|$pixels';
}

/// Приехавшее: чем рисовать и сколько оно весило.
class _Kept {
  const _Kept(this.image, this.bytes);

  final ImageProvider image;
  final int bytes;
}

class _Request {
  _Request(this.key, this.path, this.pixels, this.stillWanted);

  final String key;
  final String path;
  final int pixels;
  final bool Function()? stillWanted;
  final Completer<void> completer = Completer<void>();
}
