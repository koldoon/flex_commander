import 'dart:async';

import 'package:fc_api/fc_api.dart';

import '../fs_node.dart';
import '../staging.dart';
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
///
/// Где лежат копии, сессия не решает: это [StagingArea], и приходит она
/// снаружи. Потому сессия и живёт в API — `dart:io` ей не нужен.
class LocalCopySession {
  LocalCopySession(this._staging, {String prefix = 'flex_commander'}) : _prefix = prefix;

  final StagingArea _staging;
  final String _prefix;

  /// Каталог со всеми копиями этой сессии; null — копировать ещё не пришлось.
  StagedDirectory? _directory;

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

    final source = await (provider as FileContentProvider).openRead(node);
    final directory = await _ensureDirectory();
    final name = '${_copied++}-${node.name}';

    return directory.write(
      name,
      source.map((chunk) {
        onBytes?.call(chunk.length);
        return chunk;
      }),
    );
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
    await directory?.dispose();
  }

  Future<StagedDirectory> _ensureDirectory() async {
    final existing = _directory;
    if (existing != null) {
      return existing;
    }
    final created = await _staging.open(_prefix);
    _directory = created;
    return created;
  }
}
