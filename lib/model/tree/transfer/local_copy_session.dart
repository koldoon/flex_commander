import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fs_node.dart';
import '../tree_provider.dart';

/// Локальные копии чужих файлов и время их жизни.
///
/// Аналог `mc_getlocalcopy` из Midnight Commander. Нужна там, где чужой файл
/// приходится отдать тому, кто умеет работать только с настоящим файлом: zip
/// читает оглавление с конца, поэтому архив внутри архива или архив на сервере
/// сперва оказывается на диске.
///
/// **Сессия владеет тем, что накопировала.** Копии живут ровно столько, сколько
/// живёт сессия, и [purge] обязателен — в `finally` или в `dispose` того, кто
/// сессию завёл. Иначе временные файлы остаются после отмены, а это худший род
/// мусора: никто не знает, когда его убирать.
class LocalCopySession {
  LocalCopySession({String prefix = 'flex_commander'}) : _prefix = prefix;

  final String _prefix;

  /// Каталог со всеми копиями этой сессии; null — копировать ещё не пришлось.
  Directory? _directory;

  /// Сессию уже убрали: копий больше нет и новых не будет.
  bool _purged = false;

  /// Сколько файлов скопировано. Ноль означает, что настоящие пути нашлись у
  /// всех, кого просили, — а это самый быстрый случай.
  int get copied => _copied;
  int _copied = 0;

  /// Путь к локальному файлу с содержимым [node].
  ///
  /// Если у провайдера узла настоящие пути ([ProviderCapabilities.realFileSystem]),
  /// возвращается путь самого узла: копировать то, что и так лежит на диске,
  /// незачем. Ровно за этим и заведён флаг — это `OPIF_REALNAMES` из Far.
  ///
  /// Иначе содержимое вычитывается во временный файл. [onBytes] зовётся по
  /// кускам: копия большого архива идёт заметное время, и молчать о ней нельзя.
  Future<String> localPathOf(FsNode node, {void Function(int bytes)? onBytes}) async {
    if (_purged) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }
    if (node.provider.capabilities.realFileSystem) {
      return node.pathString;
    }

    final provider = node.provider;
    if (provider is! FileContentProvider) {
      // Ни настоящего пути, ни байтов: взять содержимое неоткуда.
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    final target = File(p.join(await _ensureDirectory(), '${_copied++}-${node.name}'));
    final sink = target.openWrite();

    try {
      await sink.addStream(
        (await (provider as FileContentProvider).openRead(node)).map((chunk) {
          onBytes?.call(chunk.length);
          return chunk;
        }),
      );
      await sink.close();
    } on Object {
      // Недокачанный файл выглядит как целый — его нельзя оставлять даже
      // до `purge`.
      await sink.close().catchError((Object _) {});
      await target.delete().catchError((Object _) => target);
      rethrow;
    }

    return target.path;
  }

  /// Убирает всё, что накопировала сессия.
  ///
  /// Ошибку уборки не показывает: рассказывать нужно о том, из-за чего работа
  /// не вышла, а не о том, как за ней подчищали. Второй вызов ничего не делает —
  /// звать [purge] и из `finally`, и из `dispose` должно быть безопасно.
  Future<void> purge() async {
    _purged = true;
    final directory = _directory;
    _directory = null;
    if (directory == null) {
      return;
    }

    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Убрать не вышло: временный каталог переживёт нас, но молчать об
      // этом лучше, чем сбивать с толку посреди чужой ошибки.
    }
  }

  Future<String> _ensureDirectory() async {
    final existing = _directory;
    if (existing != null) {
      return existing.path;
    }
    final created = await Directory.systemTemp.createTemp('${_prefix}_');
    _directory = created;
    return created.path;
  }
}
