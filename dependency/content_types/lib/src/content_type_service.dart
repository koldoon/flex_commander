import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'content_type_table.dart';

/// Определение типа по содержимому: очередь, пул и кэш.
///
/// Спецификация — `docs/spec/content-types.md`.
class ContentTypeService implements ContentTypes {
  ContentTypeService({required int Function() concurrency, int cacheLimit = defaultCacheLimit})
    : _concurrency = concurrency,
      _cacheLimit = cacheLimit;

  /// Сколько ответов помним. Ходьба по большому дереву иначе кончилась бы тем,
  /// что кэш переживёт в памяти всё остальное.
  static const int defaultCacheLimit = 4096;

  final int Function() _concurrency;
  final int _cacheLimit;

  /// Ответы: ключ → тип. Порядок вставки и есть порядок вытеснения.
  final LinkedHashMap<String, ContentType> _known = LinkedHashMap();

  /// То, что не прочиталось. Второй раз в этот сеанс не пробуем: строка
  /// перерисовывается по многу раз, и каждая перерисовка ломилась бы в файл,
  /// который уже отказал.
  final Set<String> _failed = {};

  /// Идущее и стоящее в очереди: ключ → обещание. Отсюда и берётся тот же
  /// ответ на повторный вопрос.
  final Map<String, Future<ContentType?>> _pending = {};

  final Queue<_Request> _queue = Queue();
  int _running = 0;

  @override
  ContentType? known(FileEntry entry) => _known[_keyOf(entry)];

  @override
  Future<ContentType?> detect(FileEntry entry, Content Function() open, {bool Function()? stillWanted}) {
    // Каталоги, ссылки и «..» читать нечем: про каталог отвечает не эта служба
    // (`docs/spec/content-types.md`, §6).
    if (entry.kind != EntryKind.file) {
      return Future.value();
    }

    final key = _keyOf(entry);
    final known = _known[key];
    if (known != null) {
      return Future.value(known);
    }
    if (_failed.contains(key)) {
      return Future.value();
    }
    final pending = _pending[key];
    if (pending != null) {
      return pending;
    }

    // Нулевой размер — это и есть ответ, открывать файл незачем.
    if (entry.size == 0) {
      _remember(key, ContentTypeTable.binary);
      return Future.value(ContentTypeTable.binary);
    }

    final request = _Request(key, open, stillWanted);
    _pending[key] = request.completer.future;
    _queue.add(request);
    _pump();
    return request.completer.future;
  }

  /// Занять свободные места в пуле.
  void _pump() {
    final limit = _concurrency().clamp(1, 16);
    while (_running < limit && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      // Строка уехала с экрана, пока запрос стоял в очереди: читать её незачем,
      // и запоминать по ней нечего.
      if (request.stillWanted?.call() == false) {
        _answer(request, null);
        continue;
      }
      _running++;
      unawaited(_read(request));
    }
  }

  Future<void> _read(_Request request) async {
    ContentType? type;
    try {
      type = ContentTypeTable.of(await _head(request.open()));
    } on Object {
      // Не прочиталось — прав не хватило, источник отвалился. Это не повод
      // падать: тип нужен показу, а показ обойдётся тем, что знает по имени.
      type = null;
    }

    _running--;
    if (type == null) {
      _failed.add(request.key);
    } else {
      _remember(request.key, type);
    }
    _answer(request, type);
    _pump();
  }

  /// Начало файла — и ни байтом больше.
  ///
  /// Выход из цикла закрывает поток, и для [Content] это обычное дело, а не
  /// сбой (`docs/spec/client-server.md`, §5.1.3).
  static Future<Uint8List> _head(Content content) async {
    final builder = BytesBuilder();
    await for (final chunk in content.read()) {
      builder.add(chunk);
      if (builder.length >= ContentTypeTable.headSize) {
        break;
      }
    }

    final bytes = builder.takeBytes();
    return bytes.length > ContentTypeTable.headSize
        ? Uint8List.sublistView(bytes, 0, ContentTypeTable.headSize)
        : bytes;
  }

  void _answer(_Request request, ContentType? type) {
    _pending.remove(request.key);
    request.completer.complete(type);
  }

  void _remember(String key, ContentType type) {
    _known[key] = type;
    while (_known.length > _cacheLimit) {
      _known.remove(_known.keys.first);
    }
  }

  /// Ключ — путь, размер и дата.
  ///
  /// Не узел: узлов на этой стороне нет вовсе. Размер и дата в ключе не
  /// украшение — файл мог смениться целиком, а путь у него тот же.
  static String _keyOf(FileEntry entry) =>
      '${entry.path}|${entry.size}|${entry.modified?.microsecondsSinceEpoch ?? -1}';
}

class _Request {
  _Request(this.key, this.open, this.stillWanted);

  final String key;
  final Content Function() open;
  final bool Function()? stillWanted;
  final Completer<ContentType?> completer = Completer<ContentType?>();
}
